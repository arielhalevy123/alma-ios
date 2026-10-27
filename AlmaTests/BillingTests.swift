import XCTest
@testable import Alma

/// The server owns the numbers; the app only has to read them correctly.
final class BillingTests: XCTestCase {

    private func entitlement(_ json: String) throws -> Entitlement {
        try JSONDecoder().decode(Entitlement.self, from: Data(json.utf8))
    }

    func testDecodesFullEntitlementFromServer() throws {
        let e = try entitlement("""
        {"free_designs":3,"free_remaining":0,"subscribed":true,"plan":"plus","period_end":"2026-12-01T00:00:00+00:00",
         "monthly_allowance":30,"monthly_remaining":12,"purchased_credits":3,"remaining":15,
         "account_token":"7B9E5E0B-7D5C-4C8A-9F43-2A1D3C5B6E70"}
        """)
        XCTAssertEqual(e.plan, "plus")
        XCTAssertEqual(e.monthlyRemaining, 12)
        XCTAssertEqual(e.purchasedCredits, 3)
        XCTAssertEqual(e.accountToken, "7B9E5E0B-7D5C-4C8A-9F43-2A1D3C5B6E70")
        XCTAssertFalse(e.unlimited)
    }

    /// `/users/me/usage` and older servers send fewer fields; none may fail the decode.
    func testDecodesOlderUsageShape() throws {
        let e = try entitlement(#"{"free_designs":3,"free_used":1,"subscribed":false,"remaining":2}"#)
        XCTAssertEqual(e.remaining, 2)
        XCTAssertNil(e.accountToken)
        XCTAssertEqual(e.purchasedCredits, 0)
    }

    private func english(_ e: Entitlement) -> String {
        var text = e.meterText
        text.locale = Locale(identifier: "en")
        return String(localized: text)
    }

    func testMeterTextForFreeSubscriptionAndCredits() {
        XCTAssertEqual(english(Entitlement(freeRemaining: 2)),
                       "2 free designs left")
        let sub = Entitlement(freeRemaining: 0, subscribed: true, plan: "plus", monthlyAllowance: 30, monthlyRemaining: 12)
        XCTAssertEqual(english(sub),
                       "12 of 30 designs left this month")
        let credits = Entitlement(freeRemaining: 0, purchasedCredits: 3)
        XCTAssertEqual(english(credits), "3 designs left")
        XCTAssertEqual(english(Entitlement(unlimited: true)),
                       "Unlimited designs")
    }

    func testPlanCatalogGivesEveryProductIDToLoad() throws {
        let json = """
        {"free_designs":3,"plans":[
          {"key":"starter","monthly_designs":12,"price_usd":4.99,"apple_product_id":"alma_starter_monthly","web_product_id":"web_starter_monthly"},
          {"key":"plus","monthly_designs":30,"price_usd":9.99,"apple_product_id":"alma_plus_monthly","web_product_id":"web_plus_monthly"}],
         "credit_pack":{"designs":3,"price_usd":1.99,"apple_product_id":"alma_credits_3","web_product_id":"web_credits_3"}}
        """
        let catalog = try JSONDecoder().decode(PlanCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.allProductIDs, ["alma_starter_monthly", "alma_plus_monthly", "alma_credits_3"])
        XCTAssertEqual(catalog.creditPack.designs, 3)
    }

    func testTermsURLIsSet() {
        XCTAssertEqual(AlmaAPI.termsURL.path, "/terms")
    }
}
