import Combine
import SwiftUI
import UIKit

/// Shared UI pieces, ported from `src/components/` in the React Native app.

// MARK: - Button

/// The single CTA style the product uses. `variant` mirrors the RN `Button`'s
/// primary/secondary/ghost split.
struct AlmaButton: View {
    /// primary: terracotta, the one main action. dark: charcoal, a strong second
    /// action ("Take a photo"). secondary: white with a border. ghost: text only.
    enum Variant { case primary, dark, secondary, ghost }

    let title: LocalizedStringKey
    var variant: Variant = .primary
    var isLoading: Bool = false
    var isEnabled: Bool = true
    /// Asset name of a full-colour mark shown before the title (the Google "G").
    /// Rendered as-is, never tinted.
    var leadingImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Keeps the button from resizing when the spinner replaces the label.
                HStack(spacing: 10) {
                    if let leadingImage {
                        Image(leadingImage)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(foreground)
                }
            }
            .font(Theme.body(Theme.Size.md, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(borderColour, lineWidth: variant == .secondary ? 1.5 : 0)
            )
        }
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
        .shadow(color: variant == .primary ? Theme.Palette.accent.opacity(0.28) : .clear, radius: 24, y: 10)
        .sensoryFeedback(.impact(weight: .light), trigger: isLoading)
    }

    private var foreground: Color {
        switch variant {
        case .primary: .white
        // Inverts with the fill: linen on charcoal in light mode, charcoal on linen in dark.
        case .dark: Theme.Palette.bg
        case .secondary, .ghost: Theme.Palette.fg
        }
    }

    private var background: Color {
        switch variant {
        case .primary: Theme.Palette.accent
        case .dark: Theme.Palette.fg
        case .secondary: Theme.Palette.bgCard
        case .ghost: .clear
        }
    }

    private var borderColour: Color {
        variant == .secondary ? Theme.Palette.lineStrong : .clear
    }
}

// MARK: - Wordmark

/// "alma." in Fraunces italic with a terracotta full stop, as in the design.
struct AlmaWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        (Text("alma") + Text(".").foregroundColor(Theme.Palette.accent))
            .font(Theme.display(size, italic: true))
            .kerning(-size * 0.025)
            .foregroundStyle(Theme.Palette.fg)
            .accessibilityLabel("Alma")
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.danger)
            Text(message)
                .font(Theme.body(Theme.Size.sm))
                .foregroundStyle(Theme.Palette.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.fgMuted)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        // One announcement for the whole banner rather than three separate elements.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step indicator

struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { step in
                    Capsule()
                        .fill(step <= current ? Theme.Palette.accent : Theme.Palette.fgSubtle.opacity(0.55))
                        .frame(height: 5)
                        .animation(.easeOut(duration: 0.2), value: current)
                }
            }
            Text("STEP \(current) OF \(total)")
                .font(Theme.body(12, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.sageInk)
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

// MARK: - Chip

/// Selectable pill used for room and palette choice.
struct AlmaChip: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(localized: title))
                .font(Theme.body(Theme.Size.base, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.Palette.fg)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .frame(minHeight: Theme.minTap)
                .background(isSelected ? Theme.Palette.sageInk : Theme.Palette.bgCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        isSelected ? Theme.Palette.sageInk : Theme.Palette.bgCard,
                        lineWidth: 1.5
                    )
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Screen scaffold

/// Common page chrome: linen background with the design's soft colour shapes in the
/// corners, safe-area padding, and a scrolling body.
struct AlmaScreen<Content: View>: View {
    var step: Int?
    /// When set, the screen scrolls this view id into sight above the keyboard
    /// (a text field together with the button under it).
    var keyboardAnchor: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()
            DecorShapes().ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if let step {
                            StepIndicator(current: step, total: 4)
                                .padding(.top, Theme.Spacing.sm)
                        }
                        content()
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xxl)
                    // A tap on empty space puts the keyboard away.
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture { dismissKeyboard() })
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: keyboardAnchor) { _, anchor in
                    guard let anchor else { return }
                    // After the keyboard has finished sliding up, so the inset is known.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(anchor, anchor: .bottom) }
                    }
                }
                // Also when the keyboard appears for a field that already had focus
                // (switching keyboards, or a hardware keyboard being disconnected).
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    guard let keyboardAnchor else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(keyboardAnchor, anchor: .bottom) }
                }
            }
        }
    }
}

/// Resigns whatever text field is active. SwiftUI's FocusState only reaches fields
/// in the same view, and the result screen needs to clear the keyboard of a sheet.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// A "Done" button above the keyboard. Multi-line fields have no return-to-dismiss.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .font(Theme.body(Theme.Size.base, weight: .semibold))
            }
        }
    }
}


/// Faint sage and terracotta shapes behind every wizard screen, as in the design.
struct DecorShapes: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Circle().fill(Theme.Palette.sage.opacity(0.4))
                    .frame(width: 240, height: 240)
                    .offset(x: geo.size.width - 170, y: -90)
                UnevenRoundedRectangle(topLeadingRadius: 110, topTrailingRadius: 110)
                    .fill(Theme.Palette.accent.opacity(0.3))
                    .frame(width: 220, height: 170)
                    .offset(x: -60, y: geo.size.height - 100)
                UnevenRoundedRectangle(topLeadingRadius: 60, topTrailingRadius: 60)
                    .fill(Theme.Palette.amber.opacity(0.55))
                    .frame(width: 120, height: 110)
                    .offset(x: -10, y: geo.size.height - 40)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A screen title with one emphasised word in terracotta italic and an amber
/// underline: "Your *room*".
struct AlmaTitle: View {
    let lead: LocalizedStringKey
    let emphasis: LocalizedStringKey
    var size: CGFloat = 42

    var body: some View {
        (Text(lead) + Text(" ") + Text(emphasis)
            .font(Theme.display(size, italic: true))
            .foregroundColor(Theme.Palette.accent)
            .underline(color: Theme.Palette.amber))
            .font(Theme.display(size))
            .kerning(-size * 0.024)
            .foregroundStyle(Theme.Palette.fg)
            .fixedSize(horizontal: false, vertical: true)
    }
}
