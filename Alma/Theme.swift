import SwiftUI

/// Alma brand system: the "Linen" palette from the Alma design canvas (09.10.2026),
/// shared with the web app and the Expo app so the three surfaces look like one product.
///
/// Linen ground, Charcoal ink, Terracotta for the one primary action, Sage and Amber as
/// decorative accents, Taupe for borders and idle states. Fraunces SemiBold (display, often
/// italic) over Figtree (body), both SIL Open Font License, bundled in `Fonts/`.
enum Theme {

    // MARK: - Colour

    enum Palette {
        // Every colour has a light and a dark value; the dark side keeps the Linen
        // character (charcoal ground, linen ink, the same terracotta and sage, a step
        // lighter so they hold contrast on charcoal). Ariel asked for dark mode on 10.10.2026.

        /// Linen — the canvas.
        static let bg = Color(light: 0xE8E0DB, dark: 0x1E1C1C)
        /// Raised surface: the upload area, inputs on linen.
        static let bgElevated = Color(light: 0xF6F1EE, dark: 0x2A2725)
        /// Cards.
        static let bgCard = Color(light: 0xFFFFFF, dark: 0x332F2C)
        static let overlay = Color(hex: 0x1E1C1C).opacity(0.55)

        /// Charcoal — text and secondary buttons.
        static let fg = Color(light: 0x1E1C1C, dark: 0xEFE8E3)
        static let fgDeep = Color(light: 0x1E1C1C, dark: 0xF6F1EE)
        /// Muted text.
        static let fgMuted = Color(light: 0x5F564C, dark: 0xB5A99A)
        /// Taupe — placeholders, idle steps, tiles.
        static let fgSubtle = Color(light: 0xB5A99A, dark: 0x7D7368)
        /// Charcoal in both modes: fills that carry white text or icons.
        static let ink = Color(hex: 0x1E1C1C)

        static let line = Color(light: 0xB5A99A, dark: 0x5F564C).opacity(0.6)
        static let lineStrong = Color(light: 0xB5A99A, dark: 0x5F564C)

        /// Terracotta — the primary action, progress and accents.
        static let accent = Color(light: 0xB05A40, dark: 0xC86B4E)
        static let accentDark = Color(light: 0x8E4632, dark: 0xB05A40)
        static let accentSoft = Color(light: 0xB05A40, dark: 0xC86B4E).opacity(0.10)
        static let accentTint = Color(light: 0xB05A40, dark: 0xC86B4E).opacity(0.18)

        /// Sage — decor shapes; `sageInk` for sage text and fills under white text.
        static let sage = Color(light: 0x5A8A7A, dark: 0x7FAE9D)
        static let sageInk = Color(light: 0x46766A, dark: 0x5A8A7A)
        /// Amber — highlights (underlines, the sparkle on "Redesigned by Alma").
        static let amber = Color(hex: 0xE0A23B)

        static let danger = Color(light: 0xB4442A, dark: 0xE07055)
        static let dangerSoft = Color(light: 0xB4442A, dark: 0xE07055).opacity(0.12)
        static let success = Color(light: 0x46766A, dark: 0x7FAE9D)
    }

    // MARK: - Type

    /// Point sizes from the RN scale. Used with `.custom(_:size:relativeTo:)` so they
    /// respond to Dynamic Type rather than being frozen — the RN app used fixed pixel
    /// sizes, which is an accessibility gap this port closes.
    enum Size {
        static let xs: CGFloat = 11
        static let sm: CGFloat = 13
        static let base: CGFloat = 15
        static let md: CGFloat = 17
        static let lg: CGFloat = 20
        static let xl: CGFloat = 26
        static let xxl: CGFloat = 34
        static let hero: CGFloat = 44
    }

    /// PostScript names, which is what iOS resolves — not the file names.
    private enum FontName {
        static let displayRegular = "Fraunces-Regular"
        static let displaySemiBold = "Fraunces-SemiBold"
        static let displayItalic = "Fraunces-SemiBoldItalic"
        static let bodyRegular = "Figtree-Regular"
        static let bodyMedium = "Figtree-Medium"
        static let bodySemiBold = "Figtree-SemiBold"
        static let bodyBold = "Figtree-Bold"
    }

    /// Maps a point size onto the nearest system text style, so Dynamic Type scales
    /// each role at a sensible rate instead of scaling everything like body text.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<14: .caption
        case ..<16: .subheadline
        case ..<18: .body
        case ..<22: .title3
        case ..<30: .title2
        case ..<38: .title
        default: .largeTitle
        }
    }

    /// Display type is SemiBold by default, as in the design; pass `.light` for the
    /// rare quiet heading.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold, italic: Bool = false) -> Font {
        let name: String
        if italic {
            name = FontName.displayItalic
        } else {
            switch weight {
            case .ultraLight, .thin, .light: name = FontName.displayRegular
            default: name = FontName.displaySemiBold
            }
        }
        return .custom(name, size: size, relativeTo: textStyle(for: size))
    }

    static func body(_ size: CGFloat = Size.base, weight: Font.Weight = .regular) -> Font {
        let name: String = switch weight {
        case .bold, .heavy, .black: FontName.bodyBold
        case .semibold: FontName.bodySemiBold
        case .medium: FontName.bodyMedium
        default: FontName.bodyRegular
        }
        return .custom(name, size: size, relativeTo: textStyle(for: size))
    }

    // MARK: - Layout

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    /// The design's soft, generous corners: 18 for buttons, 28 for big cards.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    /// Apple's minimum tap target. The RN app carried the same constant.
    static let minTap: CGFloat = 44
}

extension Color {
    /// Builds a colour from a 24-bit RGB literal, e.g. `Color(hex: 0xF6EFE4)`.
    /// A colour that follows the system light / dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// The card shadow from the RN theme (`shadow.card`).
    func almaCardShadow() -> some View {
        shadow(color: Theme.Palette.fg.opacity(0.06), radius: 20, x: 0, y: 8)
    }

    /// The CTA shadow from the RN theme (`shadow.cta`).
    func almaCTAShadow() -> some View {
        shadow(color: Theme.Palette.accent.opacity(0.28), radius: 24, x: 0, y: 10)
    }
}
