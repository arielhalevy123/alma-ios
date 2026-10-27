import Foundation

/// Alma API client — the native port of `src/api/client.ts`.
///
/// Talks to exactly the same backend as the web and Expo builds. Nothing on the
/// server changes for this app to exist.
///
///   POST /design                 multipart: image + marked_image + room_hint + palette_hint + prompt
///   GET  /design/:id             poll status
///   POST /auth/google/callback   exchange an OAuth code for an app token
///   POST /auth/apple/callback    exchange an Apple identity token
///   GET  /catalog/rooms          saved rooms
///   POST /rooms                  save a completed design
///   POST /auth/refresh           rotate an expired access token
///   DELETE /users/me             delete the account (guideline 5.1.1(v))
enum AlmaAPI {

    /// Read from `Info.plist` so the endpoint is configurable per build
    /// configuration, the same way `app.json`'s `extra.apiBaseUrl` works in Expo.
    static var baseURL: URL {
        let fallback = "https://gen-seller-production.up.railway.app"
        let configured = Bundle.main.object(forInfoDictionaryKey: "AlmaAPIBaseURL") as? String
        return URL(string: configured?.isEmpty == false ? configured! : fallback)!
    }

    /// Privacy policy and support pages, linked in-app (guideline 5.1.1(i)).
    static var privacyURL: URL { infoURL("AlmaPrivacyURL", fallback: "https://almapic.com/privacy") }
    static var supportURL: URL { infoURL("AlmaSupportURL", fallback: "https://almapic.com/support") }

    private static func infoURL(_ key: String, fallback: String) -> URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return URL(string: configured?.isEmpty == false ? configured! : fallback)!
    }

    enum APIError: LocalizedError {
        case http(status: Int, body: String)
        /// 402 from `POST /design`: the free designs are used up and there is no
        /// active subscription.
        case quotaExceeded
        case notConfigured(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                // FastAPI errors carry a readable {"detail": "..."}; show just that.
                struct Detail: Decodable { let detail: String }
                if let d = try? JSONDecoder().decode(Detail.self, from: Data(body.utf8)) {
                    return d.detail
                }
                return "Request failed (\(status)). \(body.prefix(200))"
            case .quotaExceeded:
                return String(localized: "You have used your free designs.")
            case .notConfigured(let what):
                return what
            case .cancelled:
                return "Sign-in cancelled."
            }
        }
    }

    // MARK: - Core

    private static func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        auth: String? = nil,
        contentType: String? = "application/json"
    ) async throws -> Data {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let auth { req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 402 { throw APIError.quotaExceeded }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode,
                                body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private static let decoder = JSONDecoder()

    // MARK: - Design

    /// Uploads a room photo and returns the redesign.
    ///
    /// The multipart body is built by hand because `URLSession` has no `FormData`
    /// equivalent. The boundary must not appear inside the payload, so it uses a
    /// UUID.
    static func startDesign(
        imageData: Data,
        markedImageData: Data? = nil,
        room: RoomHint?,
        palette: PaletteHint?,
        prompt: String?,
        retailers: [String] = [],
        auth: String?
    ) async throws -> DesignResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"room.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")

        if let markedImageData {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"marked_image\"; filename=\"marked.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(markedImageData)
            body.append("\r\n")
        }

        if let room { appendField("room_hint", room.rawValue) }
        if let palette { appendField("palette_hint", palette.rawValue) }
        if let prompt, !prompt.isEmpty { appendField("prompt", prompt) }
        if !retailers.isEmpty { appendField("retailers", retailers.joined(separator: ",")) }

        body.append("--\(boundary)--\r\n")

        let data = try await request(
            "/design",
            method: "POST",
            body: body,
            auth: auth,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try decoder.decode(DesignResult.self, from: data)
    }

    // MARK: - Usage and stores

    struct Usage: Decodable, Sendable {
        let freeDesigns: Int
        let remaining: Int
        let subscribed: Bool
        enum CodingKeys: String, CodingKey {
            case remaining, subscribed
            case freeDesigns = "free_designs"
        }
    }

    static func plans() async throws -> PlanCatalog {
        try decoder.decode(PlanCatalog.self, from: try await request("/billing/plans"))
    }

    static func entitlement(auth: String) async throws -> Entitlement {
        try decoder.decode(Entitlement.self, from: try await request("/billing/entitlement", auth: auth))
    }

    /// Hands the server a signed StoreKit 2 transaction (the JWS) to verify and credit.
    /// Safe to repeat: the server applies each transaction once.
    static func syncAppleTransaction(jws: String, auth: String) async throws -> Entitlement {
        let body = try JSONEncoder().encode(["signed_transaction": jws])
        return try decoder.decode(Entitlement.self,
                                  from: try await request("/billing/apple/sync", method: "POST", body: body, auth: auth))
    }

    static var termsURL: URL { infoURL("AlmaTermsURL", fallback: "https://almapic.com/terms") }

    static func usage(auth: String) async throws -> Usage {
        try decoder.decode(Usage.self, from: try await request("/users/me/usage", auth: auth))
    }

    struct Retailer: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let products: Int
        /// Display name and logo path; absent on servers older than the store logos.
        let name: String?
        let logo: String?

        /// The server's display name, else the slug title-cased ("ace-home" -> "Ace Home").
        var label: String {
            name ?? id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }

        var logoURL: URL? { logo.map { AlmaAPI.baseURL.appending(path: $0) } }
    }

    static func retailers() async throws -> [Retailer] {
        struct Body: Decodable { let retailers: [Retailer] }
        return try decoder.decode(Body.self, from: try await request("/catalog/retailers")).retailers
    }

    /// Polls a design job once.
    static func design(id: String, auth: String) async throws -> DesignResult {
        let data = try await request("/design/\(id)", auth: auth)
        return try decoder.decode(DesignResult.self, from: data)
    }

    // MARK: - Rooms

    /// A saved design as My designs shows it: the named room and its newest image.
    struct SavedDesign: Decodable, Identifiable, Sendable, Hashable {
        let roomID: String
        let name: String
        let designID: String
        let imageURL: String
        let products: [Product]
        let createdAt: String
        let roomType: String?
        let style: String?

        var id: String { roomID }

        enum CodingKeys: String, CodingKey {
            case name, products
            case roomID = "room_id"
            case designID = "design_id"
            case imageURL = "generated_image_url"
            case createdAt = "created_at"
            case roomAnalysis = "room_analysis"
        }

        private struct Analysis: Decodable {
            let roomType: String?
            let currentStyle: String?
            enum CodingKeys: String, CodingKey {
                case roomType = "room_type"
                case currentStyle = "current_style"
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roomID = try c.decode(String.self, forKey: .roomID)
            name = try c.decode(String.self, forKey: .name)
            designID = try c.decode(String.self, forKey: .designID)
            imageURL = try c.decode(String.self, forKey: .imageURL)
            products = (try? c.decode([Product].self, forKey: .products)) ?? []
            createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
            let analysis = try? c.decode(Analysis.self, forKey: .roomAnalysis)
            roomType = analysis?.roomType
            style = analysis?.currentStyle
        }

        /// "Oct 9" from the server's ISO timestamp.
        var shortDate: String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = iso.date(from: createdAt)
                ?? ISO8601DateFormatter().date(from: createdAt)
            return date?.formatted(.dateTime.month(.abbreviated).day()) ?? ""
        }
    }

    /// My designs, newest first.
    static func myDesigns(auth: String) async throws -> [SavedDesign] {
        let data = try await request("/rooms/designs/latest", auth: auth)
        return try decoder.decode([SavedDesign].self, from: data)
    }

    /// Saves a finished design under a name: a room with that name, holding the design.
    static func saveDesign(name: String, result: DesignResult, prompt: String?, auth: String) async throws {
        struct Room: Decodable { let id: String }
        let room = try decoder.decode(
            Room.self,
            from: try await request("/rooms", method: "POST",
                                    body: try JSONEncoder().encode(["name": name]), auth: auth))
        var body: [String: Any] = [
            "generated_image_url": result.imageURL ?? "",
            "products": result.products.map { p -> [String: Any] in
                ["name": p.name, "price_ils": p.priceILS, "image_url": p.imageURL,
                 "product_url": p.productURL, "category": p.category ?? "",
                 "product_id": p.productID ?? ""]
            },
        ]
        if let prompt { body["prompt"] = prompt }
        _ = try await request("/rooms/\(room.id)/designs", method: "POST",
                              body: try JSONSerialization.data(withJSONObject: body), auth: auth)
    }

    /// Deletes a saved design and its room for good. 404 if it is not the user's.
    static func deleteDesign(roomID: String, auth: String) async throws {
        _ = try await request("/rooms/\(roomID)", method: "DELETE", auth: auth)
    }

    static func renameDesign(roomID: String, to name: String, auth: String) async throws {
        _ = try await request("/rooms/\(roomID)", method: "PATCH",
                              body: try JSONEncoder().encode(["name": name]), auth: auth)
    }

    // MARK: - Account

    static func refresh(refreshToken: String) async throws -> TokenPair {
        let payload = try JSONEncoder().encode(["refresh_token": refreshToken])
        let data = try await request("/auth/refresh", method: "POST", body: payload)
        return try decoder.decode(TokenPair.self, from: data)
    }

    /// Permanently deletes the signed-in account. For Apple accounts, a fresh
    /// identity token + authorization code let the backend revoke the Apple link.
    static func deleteAccount(auth: String,
                              appleIdentityToken: String?,
                              appleAuthorizationCode: String?) async throws {
        var payload: [String: String] = [:]
        if let appleIdentityToken { payload["apple_identity_token"] = appleIdentityToken }
        if let appleAuthorizationCode { payload["apple_authorization_code"] = appleAuthorizationCode }
        _ = try await request("/users/me",
                              method: "DELETE",
                              body: try JSONEncoder().encode(payload),
                              auth: auth)
    }

    // MARK: - Auth exchanges

    static func exchangeGoogleCode(
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> AuthExchange {
        let payload = try JSONEncoder().encode([
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ])
        let data = try await request("/auth/google/callback", method: "POST", body: payload)
        return try decoder.decode(AuthExchange.self, from: data)
    }

    static func exchangeAppleToken(
        identityToken: String,
        authorizationCode: String?,
        userID: String,
        email: String?,
        name: String?
    ) async throws -> AuthExchange {
        var payload: [String: String] = [
            "identity_token": identityToken,
            "user_id": userID
        ]
        // Apple returns name and email exactly once, on first sign-in. Pass them
        // through so the backend can persist them at user creation; on every later
        // sign-in they are absent and must not be sent as empty strings.
        if let authorizationCode { payload["authorization_code"] = authorizationCode }
        if let email { payload["email"] = email }
        if let name, !name.isEmpty { payload["name"] = name }

        let data = try await request("/auth/apple/callback",
                                     method: "POST",
                                     body: try JSONEncoder().encode(payload))
        return try decoder.decode(AuthExchange.self, from: data)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
