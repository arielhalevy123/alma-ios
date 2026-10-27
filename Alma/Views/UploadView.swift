import SwiftUI
import PhotosUI

/// Step 1: the room photo, from the camera, the library, or a bundled example.
/// Port of `frontend/components/wizard/PhotoStep.tsx`. Picking a photo moves on to
/// the next step by itself; Continue is only there for coming back.
///
/// `PhotosPicker` needs no permission prompt and no usage string: the picker runs out
/// of process and hands back only what the user chose. The camera does need one
/// (`NSCameraUsageDescription`).
struct UploadView: View {
    @Binding var path: NavigationPath
    @Environment(SessionStore.self) private var session
    @Environment(StoreManager.self) private var store
    @Environment(WizardStore.self) private var wizard

    @State private var selection: PhotosPickerItem?
    @State private var isLoadingImage = false
    @State private var loadError: String?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var isShowingCamera = false

    /// Same four rooms as the website's "Or try an example" strip.
    /// Colour tiles from the design: terracotta, sage, taupe, charcoal (linen in dark mode).
    private static let examples: [(asset: String, room: RoomHint, label: LocalizedStringKey, icon: String, tile: Color, ink: Color)] = [
        ("example-living-room", .livingRoom, "Living room", "sofa", Theme.Palette.accent, .white),
        ("example-bedroom", .bedroom, "Bedroom", "bed.double", Theme.Palette.sageInk, .white),
        ("example-bathroom", .bathroom, "Bathroom", "bathtub", Theme.Palette.fgSubtle, Theme.Palette.fg),
        ("example-office", .homeOffice, "Office", "desktopcomputer", Theme.Palette.fg, Theme.Palette.bg),
    ]

    var body: some View {
        AlmaScreen(step: 1) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                AlmaTitle(lead: "Your", emphasis: "room")
                Text("A single wide shot works best. Daylight helps.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
                UsageMeterView()
            }

            if let error = loadError {
                ErrorBanner(message: error) { loadError = nil }
            }

            if let error = session.lastError {
                ErrorBanner(message: error) { session.lastError = nil }
            }

            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                photoWell
            }
            .buttonStyle(.plain)

            HStack(spacing: Theme.Spacing.sm) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    AlmaButton(title: "Take a photo", variant: .dark) {
                        isShowingCamera = true
                    }
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
                                .stroke(Theme.Palette.fg, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }

            examplesStrip

            if wizard.hasPhoto {
                AlmaButton(title: "Continue", isLoading: isLoadingImage) {
                    path.append(Route.room)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                AlmaWordmark()
                Spacer()
                Menu {
                    if session.isSignedIn {
                        if let name = session.userName, !name.isEmpty {
                            Text(name)
                        }
                        Button("My designs") { path.append(Route.myDesigns) }
                        Button("Plans and designs") { store.isPaywallPresented = true }
                        Button("Sign out") { session.signOut() }
                        Button("Delete account", role: .destructive) { isConfirmingDelete = true }
                    }
                    Divider()
                    Link("Privacy policy", destination: AlmaAPI.privacyURL)
                    Link("Support", destination: AlmaAPI.supportURL)
                } label: {
                    Image(systemName: isDeleting ? "hourglass" : "person")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.Palette.bg)
                        .frame(width: Theme.minTap, height: Theme.minTap)
                        .background(Circle().fill(Theme.Palette.fg))
                }
                .accessibilityLabel("Account")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Palette.bg)
        }
        .confirmationDialog("Delete your account?",
                            isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    isDeleting = true
                    _ = await session.deleteAccount()
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Alma account and everything saved with it. It cannot be undone.")
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .task { await session.refreshUsage() }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
    }

    private var examplesStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Or try an example")
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(Theme.Palette.fgMuted)
                .textCase(.uppercase)
                .kerning(1.6)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.examples, id: \.asset) { example in
                    Button {
                        guard let image = UIImage(named: example.asset) else { return }
                        use(image, room: example.room)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: example.icon)
                                .font(.system(size: 28, weight: .regular))
                                .frame(height: 32)
                            Text(example.label)
                                .font(Theme.body(12, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(example.ink)
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .background(example.tile)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(example.label))
                }
            }
        }
    }

    @ViewBuilder
    private var photoWell: some View {
        // Clear base + overlay: laid out directly, a landscape scaledToFill photo
        // widens the well, and the whole screen, past the display edge.
        Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: 270)
        .overlay {
          ZStack {
            if let image = wizard.photoImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    HStack(spacing: -16) {
                        Circle().fill(Theme.Palette.sage).frame(width: 56, height: 56)
                        Circle().fill(Theme.Palette.accent).frame(width: 56, height: 56)
                            .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(.white))
                        Circle().fill(Theme.Palette.fgSubtle).frame(width: 56, height: 56)
                    }
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Choose a photo")
                            .font(Theme.display(22))
                            .foregroundStyle(Theme.Palette.fg)
                        Text("Tap to upload from your phone")
                            .font(Theme.body(Theme.Size.sm + 1))
                            .foregroundStyle(Theme.Palette.fgMuted)
                    }
                }
            }
            if isLoadingImage {
                Theme.Palette.overlay
                ProgressView().tint(.white)
            }
          }
        }
        .clipped()
        .background(Theme.Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: wizard.hasPhoto ? [] : [6, 5]))
                .foregroundStyle(Theme.Palette.lineStrong)
        )
        .almaCardShadow()
        .accessibilityLabel(wizard.hasPhoto ? "Change photo" : "Choose a photo")
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoadingImage = true
        loadError = nil
        defer { isLoadingImage = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                loadError = "That image could not be read. Try another."
                return
            }
            use(uiImage)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Takes a photo from any source into the wizard and moves on to the room step.
    /// An example photo also pre-selects its room, which the user can still change.
    private func use(_ uiImage: UIImage, room: RoomHint? = nil) {
        // Re-encode rather than forwarding the original bytes: HEIC straight from
        // the camera is what the backend chokes on, and a 12-megapixel upload is
        // slow on cellular for no visible benefit. Drawing the image also bakes in
        // the camera's rotation, so the marks line up with what the user sees.
        let sized = uiImage.almaResized(maxDimension: 2048, normalize: true)
        guard let jpeg = sized.jpegData(compressionQuality: 0.85) else {
            loadError = "That image could not be prepared for upload."
            return
        }
        wizard.setPhoto(data: jpeg, image: Image(uiImage: sized), uiImage: sized)
        if let room { wizard.room = room }
        selection = nil
        path = NavigationPath()
        path.append(Route.room)
    }
}

extension UIImage {
    /// Scales the longest edge down to `maxDimension`, preserving aspect ratio.
    /// Images already smaller are returned untouched.
    /// With `normalize`, a smaller image is still redrawn so its orientation is
    /// baked into the pixels (camera photos arrive rotated by metadata).
    func almaResized(maxDimension: CGFloat, normalize: Bool = false) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension || (normalize && imageOrientation != .up) else { return self }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The system camera, wrapped for SwiftUI. Calls back with nil on cancel.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
