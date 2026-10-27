import XCTest
@testable import Alma

/// Decoding is the part of this app most likely to break silently, because the
/// backend is shared with the web and Expo builds and has already been observed
/// sending the same field under two names and the same number as two types.
/// These tests pin that behaviour down.
final class DecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func product(_ json: String) throws -> Product {
        try decoder.decode(Product.self, from: Data(json.utf8))
    }

    private func design(_ json: String) throws -> DesignResult {
        try decoder.decode(DesignResult.self, from: Data(json.utf8))
    }

    // MARK: - Product

    func testPriceDecodesFromWholeNumber() throws {
        let p = try product(#"{"name":"Oak stool","price_ils":1290}"#)
        XCTAssertEqual(p.priceILS, 1290)
    }

    /// The reason `price_ils` is a `Double` and not an `Int`: the feed sends both.
    /// Decoding as `Int` throws on `1290.5` and loses the whole product card.
    func testPriceDecodesFromDecimal() throws {
        let p = try product(#"{"name":"Linen throw","price_ils":249.9}"#)
        XCTAssertEqual(p.priceILS, 249.9, accuracy: 0.001)
    }

    func testProductIDDecodesFromNumber() throws {
        let p = try product(#"{"name":"Lamp","price_ils":99,"product_id":4471}"#)
        XCTAssertEqual(p.productID, "4471")
        XCTAssertEqual(p.id, "4471")
    }

    func testProductIDDecodesFromString() throws {
        let p = try product(#"{"name":"Lamp","price_ils":99,"product_id":"sku-4471"}"#)
        XCTAssertEqual(p.productID, "sku-4471")
    }

    /// Identity has to survive a missing `product_id`, otherwise SwiftUI's `ForEach`
    /// collapses several products onto one row.
    func testIdentityFallsBackToSKUThenURL() throws {
        let withSKU = try product(#"{"name":"Rug","price_ils":500,"sku":"RUG-1"}"#)
        XCTAssertEqual(withSKU.id, "RUG-1")

        let urlOnly = try product(#"{"name":"Rug","price_ils":500,"product_url":"https://x.co/rug"}"#)
        XCTAssertEqual(urlOnly.id, "https://x.co/rug")
    }

    func testMissingOptionalFieldsDoNotThrow() throws {
        let p = try product(#"{"name":"Bare minimum"}"#)
        XCTAssertEqual(p.name, "Bare minimum")
        XCTAssertEqual(p.priceILS, 0)
        XCTAssertEqual(p.imageURL, "")
        XCTAssertNil(p.category)
    }

    func testFormattedPriceDropsCentsOnWholeAmounts() throws {
        let whole = try product(#"{"name":"A","price_ils":1290}"#)
        XCTAssertFalse(whole.formattedPrice.contains("."),
                       "a whole-shekel price should not show .00")

        let fractional = try product(#"{"name":"B","price_ils":249.9}"#)
        XCTAssertTrue(fractional.formattedPrice.contains("9"),
                      "a fractional price must keep its agorot")
    }

    // MARK: - DesignResult

    /// The backend sends the finished image as `generated_image_url`, but older
    /// responses use `image_url`. The RN client prefers the former; so must this one,
    /// or a response carrying both shows the wrong picture.
    func testGeneratedImageURLWinsOverImageURL() throws {
        let d = try design("""
        {"generated_image_url":"https://x.co/new.jpg","image_url":"https://x.co/old.jpg"}
        """)
        XCTAssertEqual(d.imageURL, "https://x.co/new.jpg")
    }

    func testFallsBackToImageURLWhenGeneratedAbsent() throws {
        let d = try design(#"{"image_url":"https://x.co/only.jpg"}"#)
        XCTAssertEqual(d.imageURL, "https://x.co/only.jpg")
    }

    /// `POST /design` returns the completed design with no `status` field at all.
    /// Defaulting to anything other than `.done` leaves the result screen spinning.
    func testAbsentStatusMeansDone() throws {
        let d = try design(#"{"image_url":"https://x.co/a.jpg"}"#)
        XCTAssertEqual(d.status, .done)
    }

    func testUnrecognisedStatusDoesNotThrow() throws {
        let d = try design(#"{"status":"queued_somewhere_new"}"#)
        XCTAssertEqual(d.status, .done, "an unknown status must not fail the whole decode")
    }

    func testAbsentProductsBecomesEmptyArray() throws {
        let d = try design(#"{"image_url":"https://x.co/a.jpg"}"#)
        XCTAssertTrue(d.products.isEmpty)
    }

    func testErrorStatusCarriesMessage() throws {
        let d = try design(#"{"status":"error","error":"model timed out"}"#)
        XCTAssertEqual(d.status, .error)
        XCTAssertEqual(d.error, "model timed out")
    }

    // MARK: - Wire contract

    /// These raw values are the contract with the backend. Renaming a Swift case is
    /// free; changing its raw value silently breaks the upload.
    func testRoomHintRawValuesMatchBackend() {
        XCTAssertEqual(RoomHint.livingRoom.rawValue, "living_room")
        XCTAssertEqual(RoomHint.homeOffice.rawValue, "home_office")
        XCTAssertEqual(RoomHint.diningRoom.rawValue, "dining_room")
        XCTAssertEqual(RoomHint.kidsRoom.rawValue, "kids_room")
        XCTAssertEqual(RoomHint.allCases.count, 9)
    }

    func testPaletteHintRawValuesMatchBackend() {
        XCTAssertEqual(PaletteHint.warmNeutrals.rawValue, "warm_neutrals")
        XCTAssertEqual(PaletteHint.coolGrays.rawValue, "cool_grays")
        XCTAssertEqual(PaletteHint.earthyGreens.rawValue, "earthy_greens")
        XCTAssertEqual(PaletteHint.boldAccents.rawValue, "bold_accents")
        XCTAssertEqual(PaletteHint.lightAiry.rawValue, "light_airy")
        XCTAssertEqual(PaletteHint.allCases.count, 6)
    }

    // MARK: - Auth

    /// `/auth/apple/callback` returns `name: ""` or null for a user who withheld it
    /// from Apple; that must not fail the whole sign-in.
    func testAuthExchangeToleratesMissingNameAndCarriesRefreshToken() throws {
        let json = #"{"token":"t","access_token":"t","refresh_token":"r","user_id":"u","name":null,"email":null}"#
        let a = try decoder.decode(AuthExchange.self, from: Data(json.utf8))
        XCTAssertEqual(a.token, "t")
        XCTAssertEqual(a.name, "")
        XCTAssertNil(a.email)
        XCTAssertEqual(a.refreshToken, "r")
    }

    func testTokenPairDecodesRefreshResponse() throws {
        let json = #"{"access_token":"a2","refresh_token":"r2","token_type":"bearer","user_id":"u","expires_in":900}"#
        let p = try decoder.decode(TokenPair.self, from: Data(json.utf8))
        XCTAssertEqual(p.accessToken, "a2")
        XCTAssertEqual(p.refreshToken, "r2")
    }

    /// Google iOS OAuth clients only accept the reversed client id as redirect scheme.
    @MainActor
    func testReversedGoogleClientIDMatchesInfoPlistScheme() {
        let reversed = SessionStore.reversedClientID("987536260876-9ki89nih85f4bip7v4j1opbmfdb85gvm.apps.googleusercontent.com")
        XCTAssertEqual(reversed, "com.googleusercontent.apps.987536260876-9ki89nih85f4bip7v4j1opbmfdb85gvm")
    }

    /// The redirect only returns to the app if Info.plist registers that scheme.
    @MainActor
    func testInfoPlistRegistersTheGoogleRedirectScheme() throws {
        let clientID = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "AlmaGoogleClientID") as? String)
        XCTAssertFalse(clientID.isEmpty)
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(SessionStore.reversedClientID(clientID)))
        XCTAssertTrue(schemes.contains("alma"))
    }

    func testUsageDecodesFromServer() throws {
        let json = #"{"free_designs":3,"free_used":1,"subscribed":false,"remaining":2}"#
        let usage = try JSONDecoder().decode(AlmaAPI.Usage.self, from: Data(json.utf8))
        XCTAssertEqual(usage.remaining, 2)
        XCTAssertEqual(usage.freeDesigns, 3)
        XCTAssertFalse(usage.subscribed)
    }

    func testRetailerLabelFromSlug() {
        XCTAssertEqual(AlmaAPI.Retailer(id: "ace-home", products: 1, name: nil, logo: nil).label, "Ace Home")
        XCTAssertEqual(AlmaAPI.Retailer(id: "foxhome", products: 1, name: nil, logo: nil).label, "Foxhome")
        XCTAssertEqual(AlmaAPI.Retailer(id: "hootam", products: 1, name: "חותם", logo: nil).label, "חותם")
    }
}
