import PhotosUI
import SwiftUI

/// Find real products by describing them, by a photo of something similar, or both,
/// limited to the stores the user picks. Free: no design is used.
struct SearchView: View {
    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var photo: UIImage?
    @State private var photoData: Data?
    @State private var selection: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var stores: [AlmaAPI.Retailer] = []
    @State private var picked: Set<String> = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var hits: [AlmaAPI.SearchHit]?
    @FocusState private var isQueryFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.sm)]

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil
    }

    var body: some View {
        AlmaScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                AlmaTitle(lead: "Find", emphasis: "products")
                Text("Describe what you are looking for, or add a photo of something similar.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
            }

            if let error {
                ErrorBanner(message: error) { self.error = nil }
            }

            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.fgMuted)
                    .padding(.top, 2)
                TextField("For example: a small grey sofa for the living room", text: $query, axis: .vertical)
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fg)
                    .lineLimit(1...4)
                    .submitLabel(.search)
                    .focused($isQueryFocused)
                    .onSubmit { Task { await search() } }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 14)
            .background(Theme.Palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(Theme.Palette.lineStrong, lineWidth: 1.5)
            )

            if let photo {
                HStack(spacing: Theme.Spacing.md) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Searching for items like this photo")
                        .font(Theme.body(Theme.Size.sm))
                        .foregroundStyle(Theme.Palette.fgMuted)
                    Spacer(minLength: 0)
                    Button {
                        self.photo = nil
                        photoData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.Palette.fgMuted)
                    }
                    .accessibilityLabel("Remove photo")
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        AlmaButton(title: "Take a photo", variant: .secondary) { isShowingCamera = true }
                    }
                    PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                        Label("From library", systemImage: "photo")
                            .font(Theme.body(Theme.Size.md, weight: .semibold))
                            .foregroundStyle(Theme.Palette.fg)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.Palette.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                    .stroke(Theme.Palette.line, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
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
                        AlmaChip(title: "All stores", isSelected: picked.isEmpty) { picked = [] }
                        ForEach(stores) { store in
                            StoreChip(store: store, isSelected: picked.contains(store.id)) {
                                if picked.contains(store.id) { picked.remove(store.id) } else { picked.insert(store.id) }
                            }
                        }
                    }
                }
            }

            AlmaButton(title: "Search", isLoading: isSearching, isEnabled: canSearch) {
                Task { await search() }
            }

            if let hits {
                if hits.isEmpty {
                    Text("Nothing found. Try other words or more stores.")
                        .font(Theme.body())
                        .foregroundStyle(Theme.Palette.fgMuted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("\(hits.count) results")
                            .font(Theme.body(Theme.Size.sm, weight: .semibold))
                            .foregroundStyle(Theme.Palette.fgMuted)
                            .textCase(.uppercase)
                            .kerning(0.6)
                        ForEach(hits) { hit in
                            ProductCard(product: hit.product, store: storeName(hit.retailer))
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Optional: without the list the search simply covers every store.
            stores = (try? await AlmaAPI.retailers()) ?? []
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
    }

    private func storeName(_ id: String) -> String {
        stores.first { $0.id == id }?.label ?? id
    }

    private func load(_ item: PhotosPickerItem) async {
        defer { selection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = String(localized: "That image could not be read. Try another.")
            return
        }
        use(image)
    }

    /// The server only needs to recognise the item, so a small JPEG keeps the upload quick.
    private func use(_ image: UIImage) {
        let sized = image.almaResized(maxDimension: 1024, normalize: true)
        guard let jpeg = sized.jpegData(compressionQuality: 0.8) else {
            error = String(localized: "That image could not be prepared for upload.")
            return
        }
        photo = sized
        photoData = jpeg
    }

    private func search() async {
        guard canSearch, !isSearching else { return }
        isQueryFocused = false
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            hits = try await AlmaAPI.searchProducts(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                imageData: photoData,
                retailers: Array(picked).sorted(),
                auth: session.token
            )
        } catch AlmaAPI.APIError.http(let status, _) where status == 429 {
            error = String(localized: "Too many searches. Try again in a minute.")
        } catch {
            self.error = String(localized: "Couldn't search right now. Check your connection and try again.")
        }
    }
}
