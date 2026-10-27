import Foundation

/// Wire types for the Alma backend.
///
/// Ported from the TypeScript unions in `src/api/client.ts`. The string unions there
/// become Swift enums with `String` raw values, which is a straight translation and
/// buys exhaustiveness checking the TypeScript version could only approximate.

// MARK: - Hints

enum RoomHint: String, CaseIterable, Codable, Identifiable, Sendable {
    case livingRoom = "living_room"
    case bedroom
    case bathroom
    case homeOffice = "home_office"
    case kitchen
    case diningRoom = "dining_room"
    case kidsRoom = "kids_room"
    case hallway
    case outdoor

    var id: String { rawValue }

    /// User-facing label. Localised through the string catalogue.
    var label: LocalizedStringResource {
        switch self {
        case .livingRoom: "Living room"
        case .bedroom: "Bedroom"
        case .bathroom: "Bathroom"
        case .homeOffice: "Home office"
        case .kitchen: "Kitchen"
        case .diningRoom: "Dining room"
        case .kidsRoom: "Kids' room"
        case .hallway: "Hallway"
        case .outdoor: "Outdoor"
        }
    }
}

enum PaletteHint: String, CaseIterable, Codable, Identifiable, Sendable {
    case warmNeutrals = "warm_neutrals"
    case coolGrays = "cool_grays"
    case earthyGreens = "earthy_greens"
    case boldAccents = "bold_accents"
    case lightAiry = "light_airy"
    case surprise

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .warmNeutrals: "Warm neutrals"
        case .coolGrays: "Cool greys"
        case .earthyGreens: "Earthy greens"
        case .boldAccents: "Bold accents"
        case .lightAiry: "Light and airy"
        case .surprise: "Surprise me"
        }
    }
}

// MARK: - Product

/// A buyable item returned alongside a redesign.
///
/// `price_ils` is decoded as `Double` because the backend has been observed to send
/// both `1290` and `1290.0`. Decoding it as `Int` would throw on the latter.
struct Product: Codable, Identifiable, Hashable, Sendable {
    let sku: String?
    let productID: String?
    let name: String
    let priceILS: Double
    let imageURL: String
    let productURL: String
    let category: String?

    /// `product_id` arrives as either a number or a string depending on the retailer
    /// feed, so it is decoded leniently rather than pinned to one type.
    var id: String { productID ?? sku ?? productURL }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "ILS"
        formatter.maximumFractionDigits = priceILS.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: priceILS)) ?? "₪\(Int(priceILS))"
    }

    enum CodingKeys: String, CodingKey {
        case sku, name, category
        case productID = "product_id"
        case priceILS = "price_ils"
        case imageURL = "image_url"
        case productURL = "product_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sku = try c.decodeIfPresent(String.self, forKey: .sku)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        priceILS = try c.decodeIfPresent(Double.self, forKey: .priceILS) ?? 0
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        productURL = try c.decodeIfPresent(String.self, forKey: .productURL) ?? ""

        // product_id may be a number or a string.
        if let asString = try? c.decodeIfPresent(String.self, forKey: .productID) {
            productID = asString
        } else if let asInt = try? c.decodeIfPresent(Int.self, forKey: .productID) {
            productID = String(asInt)
        } else {
            productID = nil
        }
    }

    /// Memberwise init for previews and tests.
    init(sku: String? = nil,
         productID: String? = nil,
         name: String,
         priceILS: Double,
         imageURL: String = "",
         productURL: String = "",
         category: String? = nil) {
        self.sku = sku
        self.productID = productID
        self.name = name
        self.priceILS = priceILS
        self.imageURL = imageURL
        self.productURL = productURL
        self.category = category
    }
}

// MARK: - Design

enum DesignStatus: String, Codable, Sendable {
    case pending, processing, done, error
}

/// Decode-only: the app never sends a `DesignResult` back. That also lets
/// `CodingKeys` carry `generated_image_url`, which the backend sends but which has no
/// property of its own — it is folded into `imageURL` below.
struct DesignResult: Decodable, Sendable {
    var status: DesignStatus
    var beforeURL: String?
    var imageURL: String?
    var products: [Product]
    var error: String?

    enum CodingKeys: String, CodingKey {
        case status, products, error
        case beforeURL = "before_url"
        case imageURL = "image_url"
        // The backend has two spellings for the same field; see AlmaAPI.startDesign.
        case generatedImageURL = "generated_image_url"
    }

    init(status: DesignStatus,
         beforeURL: String? = nil,
         imageURL: String? = nil,
         products: [Product] = [],
         error: String? = nil) {
        self.status = status
        self.beforeURL = beforeURL
        self.imageURL = imageURL
        self.products = products
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An absent or unrecognised status means the job is finished: `POST /design`
        // returns the completed design with no status field at all.
        status = (try? c.decodeIfPresent(DesignStatus.self, forKey: .status)) ?? .done
        beforeURL = try c.decodeIfPresent(String.self, forKey: .beforeURL)
        // `generated_image_url` wins when both are present, matching the RN client.
        let generated = try c.decodeIfPresent(String.self, forKey: .generatedImageURL)
        imageURL = try generated ?? c.decodeIfPresent(String.self, forKey: .imageURL)
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Auth

struct AuthExchange: Decodable, Sendable {
    let token: String
    let name: String
    let email: String?
    /// Long-lived token for `POST /auth/refresh`. The access token lasts 15 minutes.
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case token, name, email
        case refreshToken = "refresh_token"
    }

    init(token: String, name: String, email: String?, refreshToken: String?) {
        self.token = token
        self.name = name
        self.email = email
        self.refreshToken = refreshToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        // A user who withheld their name from Apple has none; null must not fail sign-in.
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
    }
}

/// `POST /auth/refresh` response.
struct TokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}


// MARK: - Plans and entitlement

/// What the server says the user can still do. One shape for the app and the web,
/// from `GET /billing/entitlement`.
struct Entitlement: Decodable, Equatable, Sendable {
    let freeDesigns: Int
    let freeRemaining: Int
    let subscribed: Bool
    let plan: String?
    let monthlyAllowance: Int
    let monthlyRemaining: Int
    let purchasedCredits: Int
    let remaining: Int
    let unlimited: Bool
    /// UUID the app hands StoreKit as `appAccountToken`, so Apple's notifications
    /// can be matched to this account. Only present on `/billing/*` responses.
    let accountToken: String?
    let periodEnd: String?

    enum CodingKeys: String, CodingKey {
        case subscribed, plan, remaining, unlimited
        case freeDesigns = "free_designs"
        case freeRemaining = "free_remaining"
        case monthlyAllowance = "monthly_allowance"
        case monthlyRemaining = "monthly_remaining"
        case purchasedCredits = "purchased_credits"
        case accountToken = "account_token"
        case periodEnd = "period_end"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        freeDesigns = try c.decodeIfPresent(Int.self, forKey: .freeDesigns) ?? 3
        freeRemaining = try c.decodeIfPresent(Int.self, forKey: .freeRemaining) ?? 0
        subscribed = try c.decodeIfPresent(Bool.self, forKey: .subscribed) ?? false
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        monthlyAllowance = try c.decodeIfPresent(Int.self, forKey: .monthlyAllowance) ?? 0
        monthlyRemaining = try c.decodeIfPresent(Int.self, forKey: .monthlyRemaining) ?? 0
        purchasedCredits = try c.decodeIfPresent(Int.self, forKey: .purchasedCredits) ?? 0
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
        accountToken = try c.decodeIfPresent(String.self, forKey: .accountToken)
        periodEnd = try c.decodeIfPresent(String.self, forKey: .periodEnd)
    }

    /// Memberwise init for tests and previews.
    init(freeDesigns: Int = 3, freeRemaining: Int = 3, subscribed: Bool = false, plan: String? = nil,
         monthlyAllowance: Int = 0, monthlyRemaining: Int = 0, purchasedCredits: Int = 0,
         remaining: Int? = nil, unlimited: Bool = false, accountToken: String? = nil, periodEnd: String? = nil) {
        self.freeDesigns = freeDesigns
        self.freeRemaining = freeRemaining
        self.subscribed = subscribed
        self.plan = plan
        self.monthlyAllowance = monthlyAllowance
        self.monthlyRemaining = monthlyRemaining
        self.purchasedCredits = purchasedCredits
        self.remaining = remaining ?? (freeRemaining + monthlyRemaining + purchasedCredits)
        self.unlimited = unlimited
        self.accountToken = accountToken
        self.periodEnd = periodEnd
    }

    /// The meter line, e.g. "12 of 30 designs left this month".
    var meterText: LocalizedStringResource {
        if unlimited { return "Unlimited designs" }
        if subscribed && monthlyAllowance > 0 && monthlyRemaining > 0 {
            return "\(monthlyRemaining) of \(monthlyAllowance) designs left this month"
        }
        if freeRemaining > 0 { return "\(freeRemaining) free designs left" }
        return "\(remaining) designs left"
    }
}

/// `GET /billing/plans`: the single source for product ids and per-plan allowances,
/// so the app never hard-codes a number that the server also knows.
struct PlanCatalog: Decodable, Sendable {
    struct Plan: Decodable, Sendable, Identifiable {
        let key: String
        let monthlyDesigns: Int
        let appleProductID: String
        var id: String { key }
        enum CodingKeys: String, CodingKey {
            case key
            case monthlyDesigns = "monthly_designs"
            case appleProductID = "apple_product_id"
        }
    }
    struct CreditPack: Decodable, Sendable {
        let designs: Int
        let appleProductID: String
        enum CodingKeys: String, CodingKey {
            case designs
            case appleProductID = "apple_product_id"
        }
    }
    let plans: [Plan]
    let creditPack: CreditPack

    enum CodingKeys: String, CodingKey {
        case plans
        case creditPack = "credit_pack"
    }

    var allProductIDs: [String] { plans.map(\.appleProductID) + [creditPack.appleProductID] }
}
