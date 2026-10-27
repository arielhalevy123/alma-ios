import SwiftUI

/// Step 2: which room is this. Optional; "Not sure" lets the backend detect it.
/// Port of `frontend/components/wizard/RoomStep.tsx`.
struct RoomView: View {
    @Binding var path: NavigationPath
    @Environment(WizardStore.self) private var wizard

    // Adaptive so the chips reflow rather than clipping at large Dynamic Type sizes.
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.sm)]

    var body: some View {
        AlmaScreen(step: 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Which room?")
                    .font(Theme.display(Theme.Size.xxl, weight: .medium))
                    .foregroundStyle(Theme.Palette.fgDeep)
                Text("Helps Alma pick the right furniture. Not sure? Alma will tell.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                AlmaChip(title: "Not sure", isSelected: wizard.room == nil) {
                    wizard.room = nil
                }
                ForEach(RoomHint.allCases) { room in
                    AlmaChip(title: room.label, isSelected: wizard.room == room) {
                        wizard.room = room
                    }
                }
            }

            AlmaButton(title: "Continue") {
                path.append(Route.mark)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
