import SwiftUI

/// Gotham glass tokens from the 1.3 prototype `:root`. Dark only: the app forces darkAqua at launch.
enum Gotham {
    static let void = Color(hex: "030304")
    static let mat = Color(hex: "0B0B0E").opacity(0.84)
    static let edge = Color.white.opacity(0.07)
    static let fg = Color(hex: "ECECEF")
    static let mute = Color(hex: "ECECF2").opacity(0.4)
    static let tint = Color(hex: "141419").opacity(0.66)
    static let hi = Color.white.opacity(0.15)
    static let row = Color.white.opacity(0.045)
    static let approve = Color(hex: "F1F1F3")
    static let skipped = Color(hex: "4D4E56")
    static let run = Color.white

    /// The "changes requested" colour, keyed by the `signalColour` setting. Unknown keys fall back to amber.
    static let signalHex: [String: String] = [
        "amber": "D29B45", "crimson": "D0473A", "ice": "8CC4F2", "mono": "9A9BA3",
    ]
    static func signal(_ key: String) -> Color {
        Color(hex: signalHex[key, default: "D29B45"])
    }

    /// Thin display numerals for the clock, stats and dial. Add `.monospacedDigit()` where digits move.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .ultraLight)
    }
}

extension View {
    /// Small-caps label: 9.5 pt semibold, 0.2 em tracking, uppercase, muted.
    func cap() -> some View {
        font(.system(size: 9.5, weight: .semibold))
            .tracking(1.9)
            .textCase(.uppercase)
            .foregroundStyle(Gotham.mute)
    }
}
