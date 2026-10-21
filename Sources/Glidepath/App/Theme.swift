import SwiftUI
import AppKit

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
    /// Post and Discard on a draft row's line 2, and the room the status keeps clear of them.
    static let draftActionsWidth: CGFloat = 100
    static let profileFull: CGFloat = 64
    static let profileQuiet: CGFloat = 36
    static let footerRow: CGFloat = 44
    /// The popover never grows past this. Past it, the list scrolls.
    static let popoverMaxHeight: CGFloat = 640
}

/// Window colour tokens from docs/design/v1.2 (base.css `:root` dark, `:root[data-theme="light"]` light).
/// Each token is dynamic: the app follows the system appearance.
enum WinTheme {
    static let ground = token(0xFBFBFC, dark: 0x0A0A0B)
    static let surface = token(0xF1F1F3, dark: 0x141416)
    static let raised = token(0xE8E8EC, dark: 0x1D1D20)
    static let active = token(0xE4E4E8, dark: 0x232326)
    static let line = token(0xE6E6EA, dark: 0x1F1F22)
    static let control = token(0xC9C9CF, dark: 0x3A3A3E)
    static let text = token(0x111113, dark: 0xF5F5F7)
    static let muted = token(0x55555C, dark: 0xB4B4B8)
    static let faint = token(0x6B6B72, dark: 0x8E8E93)
    static let amber = token(0xE59A00, dark: 0xFFB020)
    static let amberInk = token(0x8A5300, dark: 0xFFC966)
    static let amberBg = token(0xFFF2D6, dark: 0x2B210C)
    static let green = token(0x1B7A47, dark: 0x3DD68C)
    static let greenBg = token(0xDDF3E5, dark: 0x12301F)
    static let blue = token(0x0062D1, dark: 0x4DA3FF)
    /// The error colour (Palette.error): destructive text.
    static let red = token(0xC4242A, dark: 0xFF6B6B)
    /// A repo's square avatar: #e4e4e8 light, #26262a dark.
    static let avatar = token(0xE4E4E8, dark: 0x26262A)
    /// The ring around the selected segment: #d6d6db light, #34343a dark.
    static let segRing = token(0xD6D6DB, dark: 0x34343A)

    /// A colour that resolves to `light` or `dark` hex (0xRRGGBB) by the effective appearance.
    private static func token(_ light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

/// Window layout measurements from docs/design/v1.2/base.css, in points. Spacing scale: 4 8 12 16 20 24 32 48.
enum WinMetrics {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48

    static let windowWidth: CGFloat = 1100
    static let windowHeight: CGFloat = 720
    static let minWidth: CGFloat = 960
    static let minHeight: CGFloat = 640
    /// Titlebar zone: every title row starts at this y, level with the sidebar's brand row.
    static let titlebarZone: CGFloat = 52
    static let sidebarWidth: CGFloat = 220
    static let sidebarInset: CGFloat = 12
    static let navRow: CGFloat = 32
    static let navGap: CGFloat = 4
    static let canvasLeft: CGFloat = 32
    static let canvasRight: CGFloat = 32
    static let canvasTop: CGFloat = 52
    static let canvasBottom: CGFloat = 32
}
