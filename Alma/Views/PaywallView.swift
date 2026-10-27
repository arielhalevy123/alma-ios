import SwiftUI
import StoreKit

/// The plans and the extra-designs pack. Shown when the server answers 402, and from
/// the account menu. Prices come from the App Store (`displayPrice`), so they are in
/// the customer's own currency.
struct PaywallView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isManaging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header

                    if store.isLoading && store.products.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl)
                    }

                    ForEach(store.subscriptionProducts, id: \.id) { product in
                        PlanRow(product: product,
                                designsPerMonth: store.designsPerMonth(for: product),
                                isCurrent: isCurrent(product),
                                isBusy: store.isWorking) {
                            Task {
                                if await store.purchase(product, session: session) { dismiss() }
                            }
                        }
                    }

                    if let credits = store.creditProduct, let pack = store.catalog?.creditPack {
                        CreditsRow(product: credits, designs: pack.designs, isBusy: store.isWorking) {
                            Task {
                                if await store.purchase(credits, session: session) { dismiss() }
                            }
                        }
                    }

                    if let message = store.message {
                        ErrorBanner(message: message) { store.message = nil }
                    }

                    if store.products.isEmpty && !store.isLoading {
                        AlmaButton(title: "Try again", variant: .secondary) {
                            Task { await store.loadProducts() }
                        }
                    }

                    AlmaButton(title: "Restore purchases", variant: .ghost, isLoading: store.isWorking) {
                        Task { await store.restore(session: session) }
                    }

                    if session.entitlement?.subscribed == true {
                        AlmaButton(title: "Manage subscription", variant: .secondary) { isManaging = true }
                    }

                    disclosure
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .manageSubscriptionsSheet(isPresented: $isManaging)
        .task {
            await store.loadProducts()
            await session.refreshUsage()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(session.entitlement.map { $0.remaining <= 0 && !$0.unlimited } == true
                 ? "You are out of designs" : "Plans and designs")
                .font(Theme.display(Theme.Size.xxl, weight: .medium))
                .foregroundStyle(Theme.Palette.fgDeep)
            if let entitlement = session.entitlement {
                Text(entitlement.meterText)
                    .font(Theme.body(Theme.Size.base, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accentDark)
                if entitlement.purchasedCredits > 0 {
                    Text("\(entitlement.purchasedCredits) extra designs, never expire")
                        .font(Theme.body(Theme.Size.sm))
                        .foregroundStyle(Theme.Palette.fgMuted)
                }
            }
            Text("Choose a monthly plan, or add a few designs once.")
                .font(Theme.body())
                .foregroundStyle(Theme.Palette.fgMuted)
        }
    }

    /// What Apple requires next to the purchase buttons (guideline 3.1.2).
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Plans renew every month at the price shown until you cancel. Payment is charged to your Apple ID. Your subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period. Manage or cancel any time in Settings > your name > Subscriptions. Monthly designs reset each month and do not roll over. Extra designs never expire.")
            HStack(spacing: Theme.Spacing.md) {
                Link("Terms of use", destination: AlmaAPI.termsURL)
                Link("Privacy policy", destination: AlmaAPI.privacyURL)
            }
            .font(Theme.body(Theme.Size.xs, weight: .semibold))
        }
        .font(Theme.body(Theme.Size.xs))
        .foregroundStyle(Theme.Palette.fgMuted)
    }

    private func isCurrent(_ product: StoreKit.Product) -> Bool {
        guard let entitlement = session.entitlement, entitlement.subscribed,
              let plan = store.catalog?.plans.first(where: { $0.appleProductID == product.id }) else { return false }
        return entitlement.plan == plan.key
    }
}

private struct PlanRow: View {
    let product: StoreKit.Product
    let designsPerMonth: Int?
    let isCurrent: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(product.displayName)
                    .font(Theme.display(Theme.Size.lg, weight: .medium))
                    .foregroundStyle(Theme.Palette.fgDeep)
                if let designsPerMonth {
                    Text("\(designsPerMonth) designs a month")
                        .font(Theme.body(Theme.Size.sm))
                        .foregroundStyle(Theme.Palette.fgMuted)
                }
                Text("\(product.displayPrice) / month")
                    .font(Theme.body(Theme.Size.base, weight: .semibold))
                    .foregroundStyle(Theme.Palette.fg)
            }
            Spacer()
            Button(action: action) {
                Text(isCurrent ? "Current plan" : "Subscribe")
                    .font(Theme.body(Theme.Size.base, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.Palette.fgMuted : .white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: Theme.minTap)
                    .background(isCurrent ? Theme.Palette.bgElevated : Theme.Palette.accent)
                    .clipShape(Capsule())
            }
            .disabled(isCurrent || isBusy)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

private struct CreditsRow: View {
    let product: StoreKit.Product
    let designs: Int
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(designs) extra designs")
                    .font(Theme.display(Theme.Size.lg, weight: .medium))
                    .foregroundStyle(Theme.Palette.fgDeep)
                Text("One time. They never expire.")
                    .font(Theme.body(Theme.Size.sm))
                    .foregroundStyle(Theme.Palette.fgMuted)
            }
            Spacer()
            Button(action: action) {
                Text(product.displayPrice)
                    .font(Theme.body(Theme.Size.base, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accentDark)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: Theme.minTap)
                    .overlay(Capsule().stroke(Theme.Palette.accent, lineWidth: 1.5))
            }
            .disabled(isBusy)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

/// "12 of 30 designs left this month". Tapping it opens the plans.
struct UsageMeterView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StoreManager.self) private var store

    var body: some View {
        if let entitlement = session.entitlement {
            Button { store.isPaywallPresented = true } label: {
                Text(entitlement.meterText)
                    .font(Theme.body(Theme.Size.sm, weight: .semibold))
                    .foregroundStyle(entitlement.remaining > 0 ? Theme.Palette.accentDark : Theme.Palette.danger)
            }
            .buttonStyle(.plain)
        }
    }
}
