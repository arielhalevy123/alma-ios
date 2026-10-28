import SwiftUI

/// Step 4 — the redesign and the buyable products.
/// Port of `app/(main)/step-4-result.tsx`, the largest screen in the RN app.
struct ResultView: View {
    @Binding var path: NavigationPath
    @Environment(SessionStore.self) private var session
    @Environment(WizardStore.self) private var wizard
    @Environment(\.openURL) private var openURL

    /// Shows the original underneath the redesign while held.
    @State private var isShowingBefore = false
    @State private var pollTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isSaved = false
    /// Where the user asked to go while the design was unsaved; set while the
    /// "not saved" warning is up, and carried out after a save from that warning.
    @State private var pendingLeave: LeaveAction?

    /// Every way off this screen. An unsaved design is gone once the user leaves.
    enum LeaveAction { case back, anotherLook, startOver, myDesigns }

    private var result: DesignResult? { wizard.result }

    var body: some View {
        AlmaScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                AlmaTitle(lead: "Your room,", emphasis: "reimagined", size: 38)
                if let count = result?.products.count, count > 0 {
                    Text("^[\(count) piece](inflect: true) you can buy today.")
                        .font(Theme.body())
                        .foregroundStyle(Theme.Palette.fgMuted)
                }
                if isSaved {
                    Button { leave(.myDesigns) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                            Text("Saved")
                            Text("·")
                            Text("Go to My designs").underline()
                        }
                        .font(Theme.body(Theme.Size.sm + 1, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            imagePane

            if let error = wizard.errorMessage {
                ErrorBanner(message: error) { wizard.errorMessage = nil }
            }

            if let products = result?.products, !products.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("In this room")
                            .font(Theme.body(12, weight: .bold))
                            .foregroundStyle(Theme.Palette.fgMuted)
                            .textCase(.uppercase)
                            .kerning(1.6)
                        Spacer()
                        (Text("Total ") + Text(total(products)).foregroundColor(Theme.Palette.accent).bold())
                            .font(Theme.body(Theme.Size.sm + 1, weight: .semibold))
                            .foregroundStyle(Theme.Palette.fg)
                    }

                    ForEach(products) { product in
                        productCard(product)
                    }
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                AlmaButton(title: "Try another look") { leave(.anotherLook) }
                AlmaButton(title: "My designs", variant: .secondary) { leave(.myDesigns) }
                AlmaButton(title: "Start over", variant: .ghost) { leave(.startOver) }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Our own back button, so leaving an unsaved design can ask first. (This also
        // turns off the edge swipe, which could not.)
        .navigationBarBackButtonHidden(true)
        .alert("Your design isn't saved", isPresented: Binding(
            get: { pendingLeave != nil && !isSaving }, set: { if !$0 && !isSaving { pendingLeave = nil } }
        )) {
            Button("Save") { isSaving = true }
            Button("Leave without saving", role: .destructive) {
                if let action = pendingLeave { perform(action) }
                pendingLeave = nil
            }
            Button("Cancel", role: .cancel) { pendingLeave = nil }
        } message: {
            Text("If you leave now, the design will be lost. Save it to My designs?")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { leave(.back) } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .principal) { AlmaWordmark(size: 24) }
            ToolbarItem(placement: .topBarTrailing) {
                if result?.imageURL != nil {
                    Button {
                        isSaving = true
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .accessibilityLabel(isSaved ? "Saved to My designs" : "Save to My designs")
                    .disabled(isSaved)
                }
            }
        }
        .sheet(isPresented: $isSaving, onDismiss: {
            // Saved from the "not saved" warning: now go where the user was heading.
            if isSaved, let action = pendingLeave { perform(action) }
            pendingLeave = nil
        }) {
            SaveDesignSheet(defaultName: defaultName) { name in
                guard let result, let auth = session.token else { return false }
                do {
                    try await AlmaAPI.saveDesign(name: name, result: result,
                                                 prompt: wizard.prompt.isEmpty ? nil : wizard.prompt,
                                                 auth: auth)
                    isSaved = true
                    return true
                } catch {
                    wizard.errorMessage = "Couldn't save the design. Try again."
                    return false
                }
            }
            .presentationDetents([.height(340)])
            .presentationCornerRadius(28)
        }
        .task { await pollIfStillWorking() }
        .onAppear { if wizard.resultIsSaved { isSaved = true } }
        .onChange(of: isSaved) { _, saved in if saved { wizard.resultIsSaved = true } }
        .onDisappear {
            // Without this the polling task keeps running after the user backs out.
            // The RN implementation leaked its interval in exactly this case.
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Leaving

    private func leave(_ action: LeaveAction) {
        dismissKeyboard()
        // Nothing to lose: already saved, or no finished image to save.
        if isSaved || result?.imageURL == nil {
            perform(action)
        } else {
            pendingLeave = action
        }
    }

    private func perform(_ action: LeaveAction) {
        switch action {
        case .back:
            if !path.isEmpty { path.removeLast() }
        case .anotherLook:
            wizard.resetForNewStyle()
            // Back to mark & tell with the photo, room and note kept.
            path = NavigationPath()
            path.append(Route.room)
            path.append(Route.mark)
        case .startOver:
            wizard.reset()
            path = NavigationPath()
        case .myDesigns:
            path = NavigationPath()
            path.append(Route.myDesigns)
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imagePane: some View {
        // A fixed-size clear base with the image as an overlay: a scaledToFill image
        // laid out directly would size the pane to its own aspect ratio and push the
        // whole screen wider than the display.
        Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: 369)
        .overlay {
          ZStack {
            if isShowingBefore, let image = wizard.photoImage {
                image.resizable().scaledToFill()
            } else if let urlString = result?.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(systemImage: "exclamationmark.triangle",
                                    text: "The image could not be loaded.")
                    default:
                        placeholder(systemImage: nil, text: nil)
                    }
                }
            } else {
                placeholder(systemImage: nil, text: "Working on it…")
            }
          }
        }
        .clipped()
        .background(Theme.Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white, lineWidth: 4))
        .shadow(color: Theme.Palette.fg.opacity(0.16), radius: 30, y: 18)
        .overlay(alignment: .topLeading) {
            if result?.imageURL != nil {
                HStack(spacing: 6) {
                    Text(isShowingBefore ? "BEFORE" : "AFTER")
                        .font(Theme.body(12, weight: .bold)).kerning(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 28)
                        // Fixed charcoal: Palette.fg turns light in dark mode, under white text.
                        .background(Capsule().fill(isShowingBefore ? Theme.Palette.ink : Theme.Palette.accent))
                    if let palette = wizard.palette {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.Palette.sage).frame(width: 8, height: 8)
                            Text(palette.label)
                        }
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)  // on a white chip in both modes
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(.white))
                    }
                }
                .padding(12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if wizard.photoImage != nil && result?.imageURL != nil {
                Label("Hold to compare", systemImage: "arrow.left.and.right")
                    .font(Theme.body(Theme.Size.sm + 1, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(Capsule().fill(Theme.Palette.ink))
                    .padding(10)
            }
        }
        // A press-and-hold comparison rather than a toggle: it keeps the
        // before/after relationship obvious without a second control.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isShowingBefore { isShowingBefore = true } }
                .onEnded { _ in isShowingBefore = false }
        )
        .accessibilityLabel("The redesigned room")
    }

    @ViewBuilder
    private func placeholder(systemImage: String?, text: LocalizedStringKey?) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.Palette.fgSubtle)
            } else {
                ProgressView().tint(Theme.Palette.accent)
            }
            if let text {
                Text(text)
                    .font(Theme.body(Theme.Size.sm))
                    .foregroundStyle(Theme.Palette.fgMuted)
            }
        }
    }

    // MARK: - Products

    private func productCard(_ product: Product) -> some View {
        ProductCard(product: product)
    }

    private func total(_ products: [Product]) -> String {
        let sum = products.reduce(0) { $0 + $1.priceILS }
        return sum.formatted(.currency(code: "ILS").precision(.fractionLength(0)))
    }

    /// "Living room · Warm neutrals", from the wizard's answers.
    private var defaultName: String {
        let room = wizard.room.map { String(localized: $0.label) } ?? String(localized: "My room")
        guard let palette = wizard.palette else { return room }
        return "\(room) · \(String(localized: palette.label))"
    }

    // MARK: - Polling

    /// `POST /design` currently returns the finished design synchronously, but the
    /// wire format carries `pending` and `processing`, so this handles them rather
    /// than showing an empty screen if the backend ever goes async.
    private func pollIfStillWorking() async {
        guard let status = result?.status, status == .pending || status == .processing,
              let id = wizard.designID, let auth = session.token else { return }

        pollTask = Task {
            // Bounded: give up after roughly two minutes rather than polling forever.
            for _ in 0..<60 {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let updated = try? await AlmaAPI.design(id: id, auth: auth) else { continue }
                wizard.result = updated
                if updated.status == .done || updated.status == .error {
                    if updated.status == .error {
                        wizard.errorMessage = updated.error ?? "The redesign failed."
                    }
                    return
                }
            }
            wizard.errorMessage = "This is taking longer than expected. Try again."
        }
        await pollTask?.value
    }
}

/// "Save design" sheet from the design: a name field and Cancel / Save.
private struct SaveDesignSheet: View {
    let defaultName: String
    /// Returns whether the save worked; the sheet closes only then.
    let save: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                AlmaTitle(lead: "Save", emphasis: "design", size: 24)
                Text("It'll appear in My designs")
                    .font(Theme.body(Theme.Size.sm + 1))
                    .foregroundStyle(Theme.Palette.fgMuted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Design name")
                    .font(Theme.body(12, weight: .bold)).kerning(1.6).textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.fgMuted)
                TextField("Design name", text: $name)
                    .font(Theme.body(16))
                    .padding(.horizontal, 16).frame(height: 54)
                    .background(Theme.Palette.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.Palette.sageInk, lineWidth: 1.5))
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
            }
            HStack(spacing: 12) {
                AlmaButton(title: "Cancel", variant: .secondary) { dismiss() }
                AlmaButton(title: "Save", isLoading: isWorking,
                           isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task {
                        isWorking = true
                        dismissKeyboard()
                        if await save(name.trimmingCharacters(in: .whitespaces)) { dismiss() }
                        isWorking = false
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.bgCard)
        .onAppear { if name.isEmpty { name = defaultName } }
        .onDisappear { dismissKeyboard() }
        .keyboardDoneButton()
    }
}
