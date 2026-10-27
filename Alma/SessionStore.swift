import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import UIKit

/// Persisted auth session — the native port of `src/state/session.ts` (Zustand).
///
/// Zustand's `create(...)` store becomes an `@Observable` class. SwiftUI tracks
/// property reads automatically, so views update without any selector or subscription
/// boilerplate.
@Observable
@MainActor
final class SessionStore: NSObject {

    private enum Key {
        static let token = "alma.session.token"
        static let name = "alma.session.name"
        static let email = "alma.session.email"
        static let refresh = "alma.session.refresh"
        static let provider = "alma.session.provider"
        /// Not secrets, so UserDefaults rather than the keychain.
        static let aiConsent = "alma.consent.aiProcessing"
    }

    private(set) var token: String?
    private(set) var userName: String?
    private(set) var userEmail: String?

    /// False until the keychain has been read, so the UI does not flash the signed-out
    /// state on launch for a user who is in fact signed in.
    private(set) var isReady = false

    var isSignedIn: Bool { token != nil }

    /// Designing needs an account: the free designs and the subscription are
    /// counted per account on the server, which is the account-based feature that
    /// makes a login legitimate under guideline 5.1.1(v).
    var canUseApp: Bool { isSignedIn }

    /// The user's balances, from `GET /billing/entitlement`. Nil until fetched or when
    /// the fetch fails; the server enforces the limit either way.
    private(set) var entitlement: Entitlement?
    var remainingDesigns: Int? { entitlement.map { $0.unlimited ? 9999 : $0.remaining } }
    var freeDesigns: Int { entitlement?.freeDesigns ?? 3 }

    func refreshUsage() async {
        guard let token else { entitlement = nil; return }
        var current = token
        do {
            entitlement = try await AlmaAPI.entitlement(auth: current)
        } catch AlmaAPI.APIError.http(status: 401, _) {
            // The 15-minute access token expired; rotate it once and retry.
            guard let fresh = await refreshAccessToken() else { return }
            current = fresh
            entitlement = try? await AlmaAPI.entitlement(auth: current)
        } catch {}
    }

    func apply(entitlement: Entitlement) { self.entitlement = entitlement }

    /// "apple" or "google": deletion re-confirms with Apple to revoke the link.
    private(set) var provider: String?
    private var refreshToken: String?

    /// Guideline 5.1.2(i): explicit permission before the photo goes to third-party AI.
    private(set) var hasAIConsent = false

    static var isGoogleConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "AlmaGoogleClientID") as? String)?.isEmpty == false
    }

    /// Set when a sign-in attempt fails, so the view can surface it.
    var lastError: String?

    // Retained for the duration of an Apple sign-in; the system controller does not
    // keep its delegate alive.
    private var appleContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var webAuthSession: ASWebAuthenticationSession?

    func load() {
        token = Keychain.get(Key.token)
        userName = Keychain.get(Key.name)
        userEmail = Keychain.get(Key.email)
        refreshToken = Keychain.get(Key.refresh)
        provider = Keychain.get(Key.provider)
        hasAIConsent = UserDefaults.standard.bool(forKey: Key.aiConsent)
        isReady = true
    }

    private func persist(_ exchange: AuthExchange, provider: String) {
        Keychain.set(exchange.token, for: Key.token)
        Keychain.set(exchange.name, for: Key.name)
        if let email = exchange.email { Keychain.set(email, for: Key.email) }
        if let refresh = exchange.refreshToken { Keychain.set(refresh, for: Key.refresh) }
        Keychain.set(provider, for: Key.provider)
        token = exchange.token
        userName = exchange.name
        userEmail = exchange.email
        refreshToken = exchange.refreshToken
        self.provider = provider
    }

    func signOut() {
        for key in [Key.token, Key.name, Key.email, Key.refresh, Key.provider] {
            Keychain.delete(key)
        }
        token = nil
        userName = nil
        userEmail = nil
        refreshToken = nil
        provider = nil
        entitlement = nil
    }

    func grantAIConsent() {
        hasAIConsent = true
        UserDefaults.standard.set(true, forKey: Key.aiConsent)
    }

    // MARK: - Account deletion

    /// Deletes the account on the server, then signs out locally. Returns false if
    /// nothing was deleted (cancelled or failed); `lastError` says why on failure.
    func deleteAccount() async -> Bool {
        guard let token else { return false }
        lastError = nil

        // For Apple accounts, confirm with Apple once more. The fresh code lets the
        // backend revoke the app's Apple link, per Apple's account-deletion guidance.
        // Cancelling the sheet cancels the deletion; any other Apple failure does
        // not block deleting our data.
        var appleToken: String?
        var appleCode: String?
        if provider == "apple" {
            do {
                let credential = try await requestAppleCredential(scopes: [])
                appleToken = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
                appleCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            } catch let error as ASAuthorizationError where error.code == .canceled {
                return false
            } catch {
                // Proceed without revocation.
            }
        }

        do {
            do {
                try await AlmaAPI.deleteAccount(auth: token,
                                                appleIdentityToken: appleToken,
                                                appleAuthorizationCode: appleCode)
            } catch AlmaAPI.APIError.http(let status, _) where status == 401 {
                // Access tokens last 15 minutes; rotate once and retry.
                guard let fresh = await refreshAccessToken() else {
                    lastError = String(localized: "Your session has expired. Sign out, sign in again, and try once more.")
                    return false
                }
                try await AlmaAPI.deleteAccount(auth: fresh,
                                                appleIdentityToken: appleToken,
                                                appleAuthorizationCode: appleCode)
            }
            signOut()
            return true
        } catch {
            lastError = String(localized: "Your account could not be deleted. Check your connection and try again.")
            return false
        }
    }

    /// Rotates the access token. Returns the new one, or nil if the session is dead.
    func refreshAccessToken() async -> String? {
        guard let refreshToken else { return nil }
        guard let pair = try? await AlmaAPI.refresh(refreshToken: refreshToken) else { return nil }
        Keychain.set(pair.accessToken, for: Key.token)
        Keychain.set(pair.refreshToken, for: Key.refresh)
        token = pair.accessToken
        self.refreshToken = pair.refreshToken
        return pair.accessToken
    }

    // MARK: - Sign in with Apple

    /// Native Sign in with Apple. This is the one place the port is genuinely simpler
    /// than the Expo version: no dependency, no config plugin, no rebuild.
    func signInWithApple() async {
        lastError = nil
        do {
            let credential = try await requestAppleCredential()
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                lastError = "Apple did not return an identity token."
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

            let exchange = try await AlmaAPI.exchangeAppleToken(
                identityToken: identityToken,
                authorizationCode: authCode,
                userID: credential.user,
                email: credential.email,
                name: name.isEmpty ? nil : name
            )
            persist(exchange, provider: "apple")
        } catch is CancellationError {
            // User dismissed the sheet — not an error worth showing.
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // Same.
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func requestAppleCredential(
        scopes: [ASAuthorization.Scope] = [.fullName, .email]
    ) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = scopes
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Sign in with Google

    /// Google OAuth through `ASWebAuthenticationSession` with PKCE — the native
    /// replacement for `expo-auth-session` + `expo-web-browser`.
    ///
    /// Mirrors the RN client exactly, including the deliberate refusal to proceed
    /// without a configured client id rather than failing somewhere less obvious.
    func signInWithGoogle() async {
        lastError = nil

        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "AlmaGoogleClientID") as? String,
              !clientID.isEmpty else {
            lastError = String(localized: "Google sign-in is not available yet.")
            return
        }

        // Google iOS clients require the reversed client id as the redirect scheme.
        let callbackScheme = Self.reversedClientID(clientID)
        let redirectURI = "\(callbackScheme):/oauth2redirect"
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        // Ties the callback to this attempt, so a stray or replayed redirect is ignored.
        let state = Self.randomCodeVerifier()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid profile email"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account")
        ]

        do {
            let callbackURL = try await presentWebAuth(url: components.url!, scheme: callbackScheme)
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if value("error") == "access_denied" { return }  // User declined on Google's page.
            guard value("state") == state, let code = value("code") else {
                lastError = String(localized: "Google sign-in did not complete. Try again.")
                return
            }
            let exchange = try await AlmaAPI.exchangeGoogleCode(
                code: code,
                redirectURI: redirectURI,
                codeVerifier: verifier
            )
            persist(exchange, provider: "google")
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Dismissed by the user.
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func presentWebAuth(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AlmaAPI.APIError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Do not reuse the Safari cookie jar for a sign-in prompt: the user should
            // see an explicit account chooser rather than being silently signed in as
            // whoever last used the browser.
            session.prefersEphemeralWebBrowserSession = true
            webAuthSession = session
            session.start()
        }
    }

    /// "123-abc.apps.googleusercontent.com" -> "com.googleusercontent.apps.123-abc"
    static func reversedClientID(_ clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    // MARK: - PKCE

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

// MARK: - Apple delegates

extension SessionStore: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                appleContinuation?.resume(throwing: AlmaAPI.APIError.cancelled)
                appleContinuation = nil
            }
            return
        }
        Task { @MainActor in
            appleContinuation?.resume(returning: credential)
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            appleContinuation?.resume(throwing: error)
            appleContinuation = nil
        }
    }
}

extension SessionStore: ASWebAuthenticationPresentationContextProviding,
                        ASAuthorizationControllerPresentationContextProviding {

    /// The two protocols declare separately-typed methods with the same base name, so
    /// both have to be implemented; they share one anchor.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        Self.anchor()
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        Self.anchor()
    }

    /// The system calls both of the above on the main thread.
    private nonisolated static func anchor() -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    /// base64url without padding, per RFC 7636.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
