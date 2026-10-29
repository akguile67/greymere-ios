import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// The studio's colours, as the server sends them for the side it is showing.
/// Until they arrive (or if they cannot be read) the app wears neutral defaults.
@MainActor @Observable
final class ThemeStore {
    var background = Color(.systemGroupedBackground)
    var surface = Color(.secondarySystemGroupedBackground)
    var text = Color.primary
    var muted = Color.secondary
    var faint = Color(.tertiaryLabel)
    var accent = Color.accentColor
    var scheme: ColorScheme? = nil

    /// The slight tint on the studio's own glass (the top pill and the Ask Godric pill), so it holds against the page.
    var glassTint: Color { accent.opacity(0.28) }

    func apply(_ r: ThemeResponse) {
        background = Color(hex: r.theme.background)
        surface = Color(hex: r.theme.surface)
        text = Color(hex: r.theme.text)
        muted = Color(hex: r.theme.textMuted)
        faint = Color(hex: r.theme.textFaint)
        accent = Color(hex: r.theme.accent)
        scheme = r.selection.variant == "dark" ? .dark : .light
    }

    static func rag(_ name: String?) -> Color {
        switch name {
        case "blue":  return Color(red: 0.31, green: 0.53, blue: 0.88)
        case "green": return Color(red: 0.30, green: 0.69, blue: 0.43)
        case "red":   return Color(red: 0.85, green: 0.33, blue: 0.31)
        default:      return Color(red: 0.88, green: 0.66, blue: 0.19)   // amber
        }
    }
}

extension Font {
    /// Titles in EB Garamond, as the studio's own screens use for headings.
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(weight == .regular ? "EBGaramond-Regular" : "EBGaramond-SemiBold", size: size, relativeTo: style)
    }
}
