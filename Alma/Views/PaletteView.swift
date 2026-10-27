import SwiftUI

/// Step 4: colour palette, then submit. Optional; "Surprise me" sends no hint.
/// Port of `frontend/components/wizard/PaletteStep.tsx`. The primary action here is
/// the redesign itself, not Continue, so there is no separate review screen.
struct PaletteView: View {
    @Binding var path: NavigationPath
    @Environment(SessionStore.self) private var session
    @Environment(WizardStore.self) private var wizard
    @Environment(StoreManager.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var isAskingConsent = false
    @State private var stores: [AlmaAPI.Retailer] = []
    @State private var startedAt: Date?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.sm)]

    var body: some View {
        AlmaScreen(step: 4) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Colours")
                    .font(Theme.display(Theme.Size.xxl, weight: .medium))
                    .foregroundStyle(Theme.Palette.fgDeep)
                Text("Pick a mood, or let Alma surprise you. Takes about a minute.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                AlmaChip(title: "Surprise me", isSelected: wizard.palette == nil) {
                    wizard.palette = nil
                }
                // `.surprise` is the same choice as the chip above; listing it twice showed two "Surprise me" chips.
                ForEach(PaletteHint.allCases.filter { $0 != .surprise }) { palette in
                    AlmaChip(title: palette.label, isSelected: wizard.palette == palette) {
                        wizard.palette = palette
                    }
                }
            }

            if !stores.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Stores")
                        .font(Theme.body(Theme.Size.sm, weight: .semibold))
                        .foregroundStyle(Theme.Palette.fgMuted)
                        .textCase(.uppercase)
                        .kerning(0.6)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                        AlmaChip(title: "All stores", isSelected: wizard.retailers.isEmpty) {
                            wizard.retailers = []
                        }
                        ForEach(stores) { store in
                            StoreChip(store: store, isSelected: wizard.retailers.contains(store.id)) {
                                if wizard.retailers.contains(store.id) {
                                    wizard.retailers.remove(store.id)
                                } else {
                                    wizard.retailers.insert(store.id)
                                }
                            }
                        }
                    }
                }
            }

            if let error = wizard.errorMessage {
                ErrorBanner(message: error) { wizard.errorMessage = nil }
            }

            AlmaButton(title: "Redesign my room",
                       isLoading: wizard.isSubmitting,
                       isEnabled: wizard.canSubmit) {
                submit()
            }
        }
        // The progress used to sit under the button, below the fold once the store
        // list is shown, so a restyle looked frozen. Now it covers the screen for every
        // generation and blocks a second tap or a step back until the call returns.
        .overlay {
            if wizard.isSubmitting {
                GenerationOverlay(startedAt: startedAt ?? .now)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: wizard.isSubmitting)
        .navigationBarBackButtonHidden(wizard.isSubmitting)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Optional: without the list the design simply uses every store.
            stores = (try? await AlmaAPI.retailers()) ?? []
        }
        .onChange(of: wizard.isOutOfDesigns) { _, isOut in
            // The server said 402: show the plans instead of a dead-end alert.
            if isOut {
                store.isPaywallPresented = true
                wizard.isOutOfDesigns = false
            }
        }
        // Guideline 5.1.2(i): name the third-party AI and get explicit permission
        // before the photo leaves the device for the first time.
        .alert("Send your photo for AI processing?", isPresented: $isAskingConsent) {
            Button("Agree and continue") {
                session.grantAIConsent()
                submit()
            }
            Button("Privacy policy") { openURL(AlmaAPI.privacyURL) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To redesign your room, Alma sends this photo and your choices to its server, where they are processed by OpenAI and Google AI services. Nothing else from your library is shared.")
        }
    }

    private func submit() {
        guard !wizard.isSubmitting else { return }
        guard session.hasAIConsent else {
            isAskingConsent = true
            return
        }
        startedAt = .now
        Task {
            // The token attributes the design to the account, which is what the
            // free designs are counted against.
            let ok = await wizard.submit(auth: session.token)
            await session.refreshUsage()
            if ok { path.append(Route.result) }
        }
    }
}

/// What the server is doing while the design runs, so the minute-long wait does
/// not look frozen. Port of `frontend/lib/loadingStages.ts`: the request is one
/// call with no progress events, so the stage is estimated from elapsed time.
struct DesignProgress: View {
    let startedAt: Date

    static let stages: [LocalizedStringResource] = [
        "Analyzing your room",
        "Selecting real products",
        "Generating your new room",
    ]

    /// Typical timings: analysis ~10 s, product selection ~15-20 s, image ~5-30 s.
    static func stage(forElapsed seconds: TimeInterval) -> Int {
        if seconds < 12 { return 0 }
        if seconds < 30 { return 1 }
        return 2
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let current = Self.stage(forElapsed: context.date.timeIntervalSince(startedAt))
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Self.stages.indices, id: \.self) { i in
                    HStack(spacing: Theme.Spacing.sm) {
                        Group {
                            if i < current {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Palette.success)
                            } else if i == current {
                                ProgressView().controlSize(.small).tint(Theme.Palette.accent)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Theme.Palette.fgSubtle)
                            }
                        }
                        .frame(width: 20)
                        Text(String(localized: Self.stages[i]))
                            .font(Theme.body(Theme.Size.sm, weight: i == current ? .semibold : .regular))
                            .foregroundStyle(i <= current ? Theme.Palette.fg : Theme.Palette.fgSubtle)
                    }
                }
                Text("This usually takes 30-60 seconds")
                    .font(Theme.body(Theme.Size.xs))
                    .foregroundStyle(Theme.Palette.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Full-screen progress for a generation: the photo, the three stages, the usual
/// wait and a bar that fills over about a minute (it never claims 100% before the
/// result arrives). Same for a first design and a restyle.
struct GenerationOverlay: View {
    let startedAt: Date
    @Environment(WizardStore.self) private var wizard

    /// Typical full run; the bar eases toward 95% over this time.
    private static let expected: TimeInterval = 60

    var body: some View {
        ZStack {
            Theme.Palette.bg.opacity(0.94).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let photo = wizard.photoUIImage {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text("Working on it…")
                    .font(Theme.display(Theme.Size.xl, weight: .medium))
                    .foregroundStyle(Theme.Palette.fgDeep)
                TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    ProgressView(value: min(0.95, elapsed / Self.expected))
                        .tint(Theme.Palette.accent)
                }
                DesignProgress(startedAt: startedAt)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
            .padding(.horizontal, Theme.Spacing.lg)
        }
        // Swallows taps so nothing underneath can start a second design.
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A store option with its logo, so people pick by the brand they know.
struct StoreChip: View {
    let store: AlmaAPI.Retailer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                AsyncImage(url: store.logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(store.label)
                    .font(Theme.body(Theme.Size.sm, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Palette.accentDark : Theme.Palette.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
            .background(isSelected ? Theme.Palette.accentTint : Theme.Palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(isSelected ? Theme.Palette.accent : Theme.Palette.line, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(store.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
