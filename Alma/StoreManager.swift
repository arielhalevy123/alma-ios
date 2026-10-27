import Foundation
import Observation
import StoreKit

/// StoreKit 2 purchases for the Alma plans and the extra-designs pack.
///
/// The App Store sells; our server decides. Every purchase, renewal and restore ends
/// the same way: the signed transaction (a JWS Apple signed) goes to
/// `POST /billing/apple/sync`, the server verifies it against Apple's certificates
/// and credits the account, and only then is the transaction finished. A transaction
/// the server has not accepted stays unfinished, so StoreKit offers it again on the
/// next launch instead of the customer losing what they paid for.
///
/// Product ids and per-plan allowances come from `GET /billing/plans`, not from this
/// file. There is deliberately no link or hint to buy outside the App Store anywhere
/// in this flow (guideline 3.1.1).
@Observable
@MainActor
final class StoreManager {

    private(set) var catalog: PlanCatalog?
    private(set) var products: [String: StoreKit.Product] = [:]
    private(set) var isLoading = false
    private(set) var isWorking = false
    var message: String?
    var isPaywallPresented = false

    private var updatesTask: Task<Void, Never>?

    // MARK: - Loading

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await AlmaAPI.plans()
            self.catalog = catalog
            let fetched = try await StoreKit.Product.products(for: catalog.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            if products.isEmpty { message = String(localized: "Plans are not available right now.") }
        } catch {
            message = String(localized: "Plans are not available right now.")
        }
    }

    var subscriptionProducts: [StoreKit.Product] {
        (catalog?.plans ?? []).compactMap { products[$0.appleProductID] }
    }

    var creditProduct: StoreKit.Product? {
        catalog.flatMap { products[$0.creditPack.appleProductID] }
    }

    func designsPerMonth(for product: StoreKit.Product) -> Int? {
        catalog?.plans.first { $0.appleProductID == product.id }?.monthlyDesigns
    }

    // MARK: - Purchasing

    /// Starts the purchase sheet. Returns true when the purchase was credited.
    func purchase(_ product: StoreKit.Product, session: SessionStore) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        message = nil
        defer { isWorking = false }

        if session.entitlement?.accountToken == nil { await session.refreshUsage() }
        guard let tokenString = session.entitlement?.accountToken, let account = UUID(uuidString: tokenString) else {
            message = String(localized: "Could not reach Alma. Check your connection and try again.")
            return false
        }

        do {
            let result = try await product.purchase(options: [.appAccountToken(account)])
            switch result {
            case .success(let verification):
                return await credit(verification, session: session)
            case .userCancelled:
                return false
            case .pending:
                message = String(localized: "Your purchase is waiting for approval. It will be added when approved.")
                return false
            @unknown default:
                return false
            }
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Restore Purchases: re-syncs with the App Store, then credits every subscription
    /// the Apple ID currently holds. Idempotent on the server, so it never refills a
    /// month that was already counted. Extra-design packs need no restore: they are
    /// already on the account.
    func restore(session: SessionStore) async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do { try await AppStore.sync() } catch {
            // The user cancelled the Apple ID prompt, or offline: current entitlements may still be local.
        }
        let found = await reconcile(session: session)
        message = found
            ? String(localized: "Your purchases have been restored.")
            : String(localized: "There was nothing to restore for this Apple ID.")
    }

    /// Sends every transaction StoreKit still holds for this Apple ID to the server.
    /// Returns whether a subscription was found. Run after sign-in and on Restore.
    @discardableResult
    func reconcile(session: SessionStore) async -> Bool {
        var foundSubscription = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productType == .autoRenewable { foundSubscription = true }
            _ = await credit(result, session: session, quiet: true)
        }
        for await result in Transaction.unfinished {
            _ = await credit(result, session: session, quiet: true)
        }
        await session.refreshUsage()
        return foundSubscription
    }

    /// Listens for transactions that arrive outside a purchase flow: renewals,
    /// purchases approved later (Ask to Buy), and ones made on another device.
    func startObservingTransactions(session: SessionStore) {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                _ = await self.credit(result, session: session, quiet: true)
            }
        }
    }

    // MARK: - Crediting

    @discardableResult
    private func credit(_ verification: VerificationResult<Transaction>, session: SessionStore, quiet: Bool = false) async -> Bool {
        guard case .verified(let transaction) = verification else {
            if !quiet { message = String(localized: "The App Store could not verify this purchase.") }
            return false
        }
        // Signed out: leave it unfinished, so it is offered again after sign-in.
        guard session.token != nil else { return false }

        do {
            let entitlement = try await sync(jws: verification.jwsRepresentation, session: session)
            session.apply(entitlement: entitlement)
            await transaction.finish()
            return true
        } catch AlmaAPI.APIError.http(status: 403, _) {
            // Belongs to a different Alma account. Finish nothing and say so once.
            if !quiet { message = String(localized: "This purchase belongs to a different Alma account.") }
            return false
        } catch {
            // Server unreachable: unfinished on purpose, retried at next launch.
            if !quiet { message = String(localized: "Your purchase went through but could not be added yet. Reopen Alma to finish; you will not be charged twice.") }
            return false
        }
    }

    private func sync(jws: String, session: SessionStore) async throws -> Entitlement {
        guard let token = session.token else { throw AlmaAPI.APIError.cancelled }
        do {
            return try await AlmaAPI.syncAppleTransaction(jws: jws, auth: token)
        } catch AlmaAPI.APIError.http(status: 401, _) {
            guard let fresh = await session.refreshAccessToken() else { throw AlmaAPI.APIError.cancelled }
            return try await AlmaAPI.syncAppleTransaction(jws: jws, auth: fresh)
        }
    }
}
