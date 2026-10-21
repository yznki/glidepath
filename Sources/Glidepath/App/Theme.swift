import SwiftUI

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

/// Colour tokens from docs/design.md. Light and dark values are chosen from the ColorScheme passed in,
/// so the live popover and the snapshot renderer use the same values.
struct Palette {
    let dark: Bool

    init(_ scheme: ColorScheme) {
        dark = scheme == .dark
    }

    var ink: Color { dark ? Color(hex: "F2F2F2") : Color(hex: "111111") }
    var secondary: Color { dark ? Color(hex: "A0A0A0") : Color(hex: "6B6B6B") }
    /// One header rule only.
    var line: Color { ink.opacity(dark ? 0.10 : 0.08) }
    /// In-progress phase, the sweep arm and active blips. The system accent, so it follows the user's setting.
    var doing: Color { .accentColor }
    var approveText: Color { dark ? Color(hex: "4CC38A") : Color(hex: "247B50") }
    var approveFill: Color { Color(hex: "30A46C") }
    var changesText: Color { dark ? Color(hex: "F2B13C") : Color(hex: "8A5A00") }
    var changesFill: Color { Color(hex: "E5A000") }
    var error: Color { dark ? Color(hex: "F97066") : Color(hex: "B42318") }
    /// The grounds the snapshots are drawn on.
    var ground: Color { dark ? Color(hex: "222222") : Color(hex: "F5F5F5") }

    func verdictText(_ v: Verdict) -> Color {
        switch v {
        case .approve: return approveText
        case .changes: return changesText
        case .skipped: return secondary
        }
    }

    func verdictFill(_ v: Verdict) -> Color {
        switch v {
        case .approve: return approveFill
        case .changes: return changesFill
        case .skipped: return secondary
        }
    }
}

/// Layout measurements from docs/design.md, in points.
enum Metrics {
    static let popoverWidth: CGFloat = 360
    static let gutter: CGFloat = 16
    static let rowPitch: CGFloat = 52
    static let rightColumn: CGFloat = 72
    static let radar: CGFloat = 92
    static let footer: CGFloat = 44
    static let railWidth: CGFloat = 44
    static let maxVisibleRows = 6
}
