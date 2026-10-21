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

/// Colour tokens from docs/design.md (design pass 3 wins). Light and dark values come from the colour
/// scheme passed in, so the live popover and the snapshot renderer use identical values.
struct Palette {
    let dark: Bool

    init(_ scheme: ColorScheme) {
        dark = scheme == .dark
    }

    func pick(_ light: String, _ darkHex: String) -> Color {
        Color(hex: dark ? darkHex : light)
    }

    var ink: Color { pick("111111", "F2F2F2") }
    var secondary: Color { pick("5C5C5C", "A8A8A8") }
    var tertiary: Color { pick("6B6B6B", "8E8E8E") }
    /// Rules: ink at a low opacity.
    var rule: Color { ink.opacity(dark ? 0.10 : 0.08) }
    /// Slope line of the approach profile.
    var slope: Color { pick("3A3A3C", "D0D0D0") }
    /// The runway bar: #D0D0D0 light, #4A4A4A dark.
    var runwayBar: Color { pick("D0D0D0", "4A4A4A") }
    /// In-progress text, and the stage word on an active row.
    var doingText: Color { pick("0060CC", "4DA3FF") }
    /// In-progress marks: the system blue.
    var doingMark: Color { .accentColor }
    var error: Color { pick("C4242A", "FF6B6B") }
    var changesText: Color { pick("8A5300", "FFC966") }
    var changesMark: Color { pick("B86E00", "FFB020") }
    var approveText: Color { pick("1B6B3F", "7EE0A6") }
    var approveMark: Color { pick("1F8A52", "3DD68C") }
    var skipMark: Color { pick("6B6B6B", "9A9A9A") }
    /// The four-dash meter: done 35%, future 12%; the current dash is the system blue.
    var meterDone: Color { ink.opacity(0.35) }
    var meterFuture: Color { ink.opacity(0.12) }
    /// The grounds the snapshots are drawn on.
    var ground: Color { pick("F5F5F5", "222222") }
}

/// Layout measurements from docs/design.md, in points. Every element lives inside a 16 pt inset.
enum Metrics {
    static let popoverWidth: CGFloat = 360
    static let inset: CGFloat = 16
    static let contentWidth: CGFloat = 328
    static let statusColumnWidth: CGFloat = 84
    /// The chevron sits in the last 14 pt of the status column, so labels never move on hover.
    static let chevronReserve: CGFloat = 12
    static let rowOneLine: CGFloat = 44
    static let rowThreeLines: CGFloat = 60
    static let profileFull: CGFloat = 64
    static let profileQuiet: CGFloat = 36
    static let footerRow: CGFloat = 44
    /// The popover never grows past this. Past it, the list scrolls.
    static let popoverMaxHeight: CGFloat = 640
}
