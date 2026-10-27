import SwiftUI
import AuthenticationServices

/// Sign-in screen — the port of `app/index.tsx`.
struct LandingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    /// Which sign-in is in flight, so only that button shows a spinner.
    @State private var working: Provider?

    private enum Provider { case apple, google }

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                WelcomeCollage()
                    .frame(height: 400)
                    .padding(.horizontal, -Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    AlmaWordmark(size: 60)

                    (Text("Photograph a room. See it redesigned, with furniture you can ")
                        + Text("actually buy.")
                            .foregroundColor(Theme.Palette.sageInk)
                            .bold()
                            .underline(color: Theme.Palette.amber))
                        .font(Theme.body(Theme.Size.md))
                        .foregroundStyle(Theme.Palette.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let error = session.lastError {
                    ErrorBanner(message: error)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Deliberately unused: the store drives its own
                        // ASAuthorizationController so the token exchange, keychain
                        // write and error handling live in one place. This button is
                        // here for Apple's required styling.
                    }
                    // Apple's guidance: the white button on dark backgrounds.
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .allowsHitTesting(false)
                    .overlay {
                        // Transparent hit target so the tap runs our flow.
                        Button {
                            Task { await run(.apple) { await session.signInWithApple() } }
                        } label: {
                            ZStack {
                                Color.clear.contentShape(Rectangle())
                                if working == .apple {
                                    ProgressView().tint(colorScheme == .dark ? .black : .white)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(colorScheme == .dark ? Color.white : Color.black)
                                }
                            }
                        }
                        .accessibilityLabel("Sign in with Apple")
                    }
                    .disabled(working != nil)

                    // Hidden until a Google OAuth client id is configured: a button
                    // that only reports an error is an App Review rejection.
                    if SessionStore.isGoogleConfigured {
                        AlmaButton(title: "Continue with Google",
                                   variant: .secondary,
                                   isLoading: working == .google,
                                   leadingImage: "google-g") {
                            Task { await run(.google) { await session.signInWithGoogle() } }
                        }
                        .disabled(working != nil)
                    }
                }

                Link(destination: AlmaAPI.privacyURL) {
                    Text("Privacy policy")
                        .font(Theme.body(Theme.Size.xs, weight: .medium))
                        .underline()
                        .foregroundStyle(Theme.Palette.fgMuted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    private func run(_ provider: Provider, _ work: () async -> Void) async {
        working = provider
        await work()
        working = nil
    }
}

/// The welcome hero from the design: soft colour shapes behind three arched room
/// photos and a "Redesigned by Alma" badge. Decorative, so hidden from VoiceOver.
private struct WelcomeCollage: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Circle().fill(Theme.Palette.accent.opacity(0.85))
                    .frame(width: 220, height: 220).offset(x: -60, y: -60)
                Circle().fill(Theme.Palette.amber.opacity(0.9))
                    .frame(width: 120, height: 120).offset(x: w / 2 - 60, y: 46)
                Circle().fill(Theme.Palette.sage.opacity(0.85))
                    .frame(width: 200, height: 200).offset(x: w - 150, y: 250)
                UnevenRoundedRectangle(topLeadingRadius: 75, topTrailingRadius: 75)
                    .fill(Theme.Palette.fgSubtle)
                    .frame(width: 150, height: 110).offset(x: -30, y: 290)

                arch("example-bedroom", width: 120, height: 200).offset(x: 16, y: 170)
                arch("example-office", width: 120, height: 200).offset(x: w - 136, y: 150)
                arch("example-living-room", width: 160, height: 290).offset(x: w / 2 - 80, y: 80)

                Label("Redesigned by Alma", systemImage: "sparkle")
                    .font(Theme.body(Theme.Size.sm, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Capsule().fill(Theme.Palette.ink))
                    .shadow(color: Theme.Palette.fg.opacity(0.25), radius: 18, y: 8)
                    .offset(x: w / 2 + 15, y: 340)
            }
            .frame(width: w, height: geo.size.height, alignment: .topLeading)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func arch(_ image: String, width: CGFloat, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: width / 2, bottomLeadingRadius: 16,
                                           bottomTrailingRadius: 16, topTrailingRadius: width / 2)
        return Image(image).resizable().scaledToFill()
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(shape.stroke(Theme.Palette.bg, lineWidth: 5))
            .shadow(color: Theme.Palette.fg.opacity(0.2), radius: 18, y: 14)
    }
}

#Preview {
    LandingView()
        .environment(SessionStore())
}
