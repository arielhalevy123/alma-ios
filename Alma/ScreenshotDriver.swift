#if DEBUG
import SwiftUI

/// Debug-only: drives the real wizard to a given step from launch arguments, so App
/// Store screenshots can be taken from the simulator without a UI-test target.
/// Compiled out of Release builds entirely.
///
///   -AlmaDemoPhoto /path/to/room.jpg  -AlmaDemoStep upload|room|mark|palette|result
///
/// `result` really calls `POST /design` on the configured backend.
@MainActor
enum ScreenshotDriver {
    static func run(session: SessionStore, wizard: WizardStore, path: Binding<NavigationPath>) async {
        let args = UserDefaults.standard
        guard let step = args.string(forKey: "AlmaDemoStep"),
              let photoPath = args.string(forKey: "AlmaDemoPhoto"),
              let uiImage = UIImage(contentsOfFile: photoPath),
              let jpeg = uiImage.almaResized(maxDimension: 2048).jpegData(compressionQuality: 0.85)
        else { return }

        // Screenshots need a signed-in simulator: designing requires an account.
        guard session.canUseApp else { return }
        wizard.setPhoto(data: jpeg, image: Image(uiImage: uiImage),
                        uiImage: uiImage.almaResized(maxDimension: 2048))
        if step == "upload" { return }

        wizard.room = RoomHint(rawValue: args.string(forKey: "AlmaDemoRoom") ?? "") ?? .livingRoom
        wizard.palette = PaletteHint(rawValue: args.string(forKey: "AlmaDemoPalette") ?? "") ?? .warmNeutrals
        path.wrappedValue.append(Route.room)
        if step == "room" { return }

        path.wrappedValue.append(Route.mark)
        if step == "mark" { return }

        path.wrappedValue.append(Route.palette)
        if step == "palette" { return }

        if await wizard.submit(auth: session.token) {
            path.wrappedValue.append(Route.result)
        }
    }
}
#endif
