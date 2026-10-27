import SwiftUI
import UIKit

/// One finger stroke on the photo. Points live in the photo's pixel space, so the
/// marks stay glued to the furniture at any display size. Port of
/// `frontend/lib/drawing.ts`.
struct MarkStroke: Equatable, Sendable {
    var points: [CGPoint]
    var width: CGFloat

    /// Translucent terracotta, the website's MARK_COLOR, so the marked item stays visible.
    static let color = UIColor(red: 191 / 255, green: 138 / 255, blue: 78 / 255, alpha: 0.55)

    /// Brush size proportional to the photo so strokes read the same on any image.
    static func brushWidth(imageWidth: CGFloat) -> CGFloat {
        max(16, (imageWidth * 0.035).rounded())
    }

    func path(scale: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
        if points.count == 1 {
            // A tap is a dot, not nothing.
            path.addLine(to: CGPoint(x: first.x * scale + 0.1, y: first.y * scale + 0.1))
        }
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale))
        }
        return path
    }

    /// Draws the strokes onto a JPEG copy of the photo: the `marked_image` the
    /// backend reads to find what to replace. Nil when nothing is marked, so the
    /// backend does a full redesign. Generation always edits the clean photo.
    static func flatten(_ strokes: [MarkStroke], onto photo: UIImage) -> Data? {
        guard !strokes.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: photo.size, format: format).image { ctx in
            photo.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setStrokeColor(color.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                cg.setLineWidth(stroke.width)
                cg.addPath(stroke.path(scale: 1).cgPath)
                cg.strokePath()
            }
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}

/// Step 3: mark & tell. The user paints over the items to replace and can add a note.
/// Both are optional. Port of `frontend/components/wizard/MarkStep.tsx`.
struct MarkView: View {
    @Binding var path: NavigationPath
    @Environment(WizardStore.self) private var wizard

    /// The stroke under the finger, committed to the store on lift.
    @State private var live: MarkStroke?
    /// Only a tap on the field opens the keyboard; nothing focuses it for the user.
    @FocusState private var isNoteFocused: Bool
    private static let noteAnchor = "note"

    var body: some View {
        @Bindable var wizard = wizard

        AlmaScreen(step: 3, keyboardAnchor: isNoteFocused ? Self.noteAnchor : nil) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Mark & tell")
                    .font(Theme.display(Theme.Size.xxl, weight: .medium))
                    .foregroundStyle(Theme.Palette.fgDeep)
                Text("Paint over what you want replaced. Skip it to redesign the whole room.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fgMuted)
            }

            if let photo = wizard.photoUIImage {
                canvas(photo)
            }

            HStack {
                Text(wizard.strokes.isEmpty
                     ? "Nothing marked: Alma redesigns the whole room."
                     : "\(wizard.strokes.count) marks")
                    .font(Theme.body(Theme.Size.sm))
                    .foregroundStyle(Theme.Palette.fgMuted)
                Spacer()
                Button("Undo") { _ = wizard.strokes.popLast() }
                    .disabled(wizard.strokes.isEmpty)
                Button("Clear") { wizard.strokes = [] }
                    .disabled(wizard.strokes.isEmpty)
            }
            .font(Theme.body(Theme.Size.sm, weight: .medium))

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Anything specific?")
                    .font(Theme.body(Theme.Size.sm, weight: .semibold))
                    .foregroundStyle(Theme.Palette.fgMuted)
                TextField("Optional, e.g. light fabric, budget-friendly, good for kids",
                          text: $wizard.prompt,
                          axis: .vertical)
                    .font(Theme.body())
                    .foregroundStyle(Theme.Palette.fg)
                    .lineLimit(3...6)
                    .focused($isNoteFocused)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Palette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Theme.Palette.line, lineWidth: 1)
                    )
            }

            AlmaButton(title: "Continue") {
                isNoteFocused = false
                path.append(Route.palette)
            }
            }
            // The note and Continue scroll into sight together when the keyboard opens.
            .id(Self.noteAnchor)
        }
        .keyboardDoneButton()
        .onAppear { isNoteFocused = false }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func canvas(_ photo: UIImage) -> some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    let scale = geo.size.width / photo.size.width
                    Canvas { ctx, _ in
                        let all = wizard.strokes + (live.map { [$0] } ?? [])
                        for stroke in all {
                            ctx.stroke(stroke.path(scale: scale),
                                       with: .color(Color(uiColor: MarkStroke.color)),
                                       style: StrokeStyle(lineWidth: stroke.width * scale,
                                                          lineCap: .round, lineJoin: .round))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = CGPoint(
                                    x: min(photo.size.width, max(0, value.location.x / scale)),
                                    y: min(photo.size.height, max(0, value.location.y / scale)))
                                if live == nil {
                                    live = MarkStroke(points: [p],
                                                      width: MarkStroke.brushWidth(imageWidth: photo.size.width))
                                } else {
                                    live?.points.append(p)
                                }
                            }
                            .onEnded { _ in
                                if let stroke = live { wizard.strokes.append(stroke) }
                                live = nil
                            }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .accessibilityLabel("Your room photo. Draw on it to mark items to replace.")
    }
}
