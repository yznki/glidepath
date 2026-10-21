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

/// Colour tokens from docs/design.md. Light and dark values come from the colour scheme passed in, so the
/// live popover and the snapshot renderer use identical values. Text is at least 4.5:1 and marks 3:1 on
/// the grounds the snapshots use.
struct Palette {
    let dark: Bool

    init(_ scheme: ColorScheme) {
        dark = scheme == .dark
    }

    func pick(_ light: String, _ darkHex: String) -> Color {
        Color(hex: dark ? darkHex : light)
    }

    var ink: Color { pick("111111", "F2F2F2") }
    var secondary: Color { pick("6B6B6B", "9A9A9A") }
    /// Meta, labels and rules: ink at a low opacity.
    var rule: Color { ink.opacity(dark ? 0.10 : 0.08) }
    var runway: Color { ink.opacity(0.25) }
    /// In-progress text, and the stage word on an active row.
    var doingText: Color { pick("0060CC", "4DA3FF") }
    /// In-progress marks: the system blue.
    var doingMark: Color { .accentColor }
    var error: Color { pick("B42318", "F97066") }
    var amber: Color { Color(hex: "E5A000") }
    var approveMark: Color { Color(hex: "30A46C") }
    var greyMark: Color { pick("767676", "8A8A8A") }
    var changesChipText: Color { pick("7A4B00", "FFC966") }
    var changesChipFill: Color { pick("FBEBC8", "3A2A0C") }
    var approveChipText: Color { pick("1B6B3F", "7EE0A6") }
    var approveChipFill: Color { pick("DDF3E4", "12301F") }
    var noResultText: Color { pick("555555", "BBBBBB") }
    var noResultFill: Color { pick("EBEBEB", "333333") }
    var meterFuture: Color { pick("C4C4C4", "555555") }
    /// The grounds the snapshots are drawn on.
    var ground: Color { pick("F5F5F5", "222222") }
    /// Count text in the menu bar glyph when changes are waiting.
    var glyphCount: Color { pick("C77700", "FFB000") }
}

/// Layout measurements from docs/design.md, in points. Every element lives between x = 16 and x = 344.
enum Metrics {
    static let popoverWidth: CGFloat = 360
    static let gutter: CGFloat = 16
    static let contentWidth: CGFloat = 328
    static let rowMinHeight: CGFloat = 52
    static let statusTrailing: CGFloat = 344
    static let chipHeight: CGFloat = 20
    static let profileHeight: CGFloat = 64
    static let footer: CGFloat = 44
    static let maxVisibleHeight: CGFloat = 380
}
