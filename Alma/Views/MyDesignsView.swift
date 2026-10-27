import SwiftUI

/// My designs: every design the user saved, newest first. Tapping one offers
/// Rename and Open. From the "4 · My designs" board in the Alma design canvas.
struct MyDesignsView: View {
    @Binding var path: NavigationPath
    @Environment(SessionStore.self) private var session
    @Environment(WizardStore.self) private var wizard

    @State private var designs: [AlmaAPI.SavedDesign] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selected: AlmaAPI.SavedDesign?
    @State private var renaming: AlmaAPI.SavedDesign?
    /// The design waiting for the user to confirm deleting it.
    @State private var deleting: AlmaAPI.SavedDesign?
    @State private var draftName = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        AlmaScreen {
            HStack(spacing: Theme.Spacing.md) {
                Text(initial)
                    .font(Theme.display(22, italic: true))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Theme.Palette.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hi, \(session.userName ?? String(localized: "there"))")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.Palette.fg)
                    Text("^[\(designs.count) design](inflect: true)")
                        .font(Theme.body(Theme.Size.sm + 1))
                        .foregroundStyle(Theme.Palette.fgMuted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                AlmaTitle(lead: "My", emphasis: "designs", size: 34)
                Text("Tap a design to open it or rename it.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
            }

            if let loadError {
                ErrorBanner(message: loadError) { self.loadError = nil }
            }

            if isLoading {
                ProgressView().tint(Theme.Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if designs.isEmpty {
                Text("Nothing saved yet. Tap the heart on a result to keep it here.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .multilineTextAlignment(.center)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(designs) { design in
                        Button { selected = design } label: { card(design) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open", systemImage: "arrow.up.forward.square") { open(design) }
                                Button("Rename", systemImage: "pencil") {
                                    draftName = design.name
                                    renaming = design
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = design }
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }

            AlmaButton(title: "New design") {
                wizard.reset()
                path = NavigationPath()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(selected?.name ?? "", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }
        ), titleVisibility: .visible) {
            if let design = selected {
                Button("Open") { open(design) }
                Button("Rename") {
                    draftName = design.name
                    renaming = design
                }
                Button("Delete", role: .destructive) { deleting = design }
                Button("Cancel", role: .cancel) {}
            }
        }
        .alert("Delete this design?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { design in
            Button("Delete", role: .destructive) { Task { await delete(design) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It can't be restored.")
        }
        .alert("Rename design", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Design name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save name") {
                guard let design = renaming else { return }
                Task { await rename(design, to: draftName) }
            }
        }
    }

    /// The catalogue's room key in the reader's language ("living_room" -> "סלון").
    private func roomLabel(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        if let room = RoomHint(rawValue: key) { return String(localized: room.label) }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var initial: String {
        String((session.userName ?? "A").prefix(1)).uppercased()
    }

    private func card(_ design: AlmaAPI.SavedDesign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay { SavedImage(urlString: design.imageURL) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let style = design.style, !style.isEmpty {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.Palette.sage).frame(width: 8, height: 8)
                            Text(style.capitalized).lineLimit(1)
                        }
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)  // on a white chip in both modes
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(.white))
                        .padding(8)
                    }
                }
            Text(design.name)
                .font(Theme.body(Theme.Size.base, weight: .semibold))
                .foregroundStyle(Theme.Palette.fg)
                .lineLimit(1)
            Text([roomLabel(design.roomType), design.shortDate]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Theme.body(Theme.Size.sm))
                .foregroundStyle(Theme.Palette.fgMuted)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.Palette.bgCard))
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let auth = session.token else { isLoading = false; return }
        do {
            designs = try await AlmaAPI.myDesigns(auth: auth)
        } catch {
            loadError = String(localized: "Couldn't load your designs. Pull to try again.")
        }
        isLoading = false
    }

    private func rename(_ design: AlmaAPI.SavedDesign, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let auth = session.token else { return }
        do {
            try await AlmaAPI.renameDesign(roomID: design.roomID, to: trimmed, auth: auth)
            await load()
        } catch {
            loadError = String(localized: "Couldn't rename the design. Try again.")
        }
    }

    private func delete(_ design: AlmaAPI.SavedDesign) async {
        guard let auth = session.token else { return }
        do {
            try await AlmaAPI.deleteDesign(roomID: design.roomID, auth: auth)
            withAnimation(.easeInOut(duration: 0.3)) {
                designs.removeAll { $0.id == design.id }
            }
        } catch {
            // The server's own words, after a line saying what failed.
            loadError = String(localized: "Couldn't delete the design.") + " " + error.localizedDescription
        }
    }

    /// Opens a saved design on the result screen.
    private func open(_ design: AlmaAPI.SavedDesign) {
        wizard.result = DesignResult(status: .done, imageURL: design.imageURL, products: design.products)
        wizard.resultIsSaved = true
        path.append(Route.result)
    }
}

/// A saved design's image: a data URL from the design endpoint, or an https URL.
private struct SavedImage: View {
    let urlString: String

    var body: some View {
        if urlString.hasPrefix("data:"), let comma = urlString.firstIndex(of: ","),
           let data = Data(base64Encoded: String(urlString[urlString.index(after: comma)...])),
           let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            AsyncImage(url: URL(string: urlString)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Theme.Palette.bgElevated
                }
            }
        }
    }
}
