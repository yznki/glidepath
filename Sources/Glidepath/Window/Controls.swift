import SwiftUI

/// The window's buttons (base.css `.btn`, `.link`): one filled primary per screen at 44 tall, outlined pills
/// at 32 (44 when `large`), and text links. A press dims at once.
struct WinButton: View {
    enum Style {
        /// Filled: white on dark, near-black on light. One per screen.
        case primary
        /// Outlined pill with the control stroke.
        case outline
        /// Blue text link.
        case link
        /// Faint text link, for the second action on a row.
        case quiet
    }

    let title: String
    var style: Style = .outline
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(WinButtonStyle(style: style, large: large))
    }
}

/// The drawing behind `WinButton`. Reads `isEnabled`, so `.disabled` dims it.
private struct WinButtonStyle: ButtonStyle {
    let style: WinButton.Style
    let large: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var isLink: Bool { style == .link || style == .quiet }
    private var isBig: Bool { style == .primary || large }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: isLink ? 13 : (isBig ? 15 : 13), weight: isBig ? .semibold : .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, isLink ? 0 : (isBig ? WinMetrics.s24 : WinMetrics.s16))
            .frame(minWidth: isBig ? 140 : 0, minHeight: isLink ? nil : (isBig ? 44 : 32),
                   maxHeight: isLink ? nil : (isBig ? 44 : 32))
            .background {
                if style == .primary { Capsule().fill(WinTheme.text) }
            }
            .overlay {
                if style == .outline { Capsule().strokeBorder(WinTheme.control, lineWidth: 1) }
            }
            .opacity(isEnabled ? (pressed ? (isLink ? 0.6 : 0.85) : 1) : 0.4)
            .animation(.easeOut(duration: 0.14), value: pressed)
            .contentShape(Rectangle())
    }

    private var ink: Color {
        switch style {
        case .primary: return WinTheme.ground
        case .outline: return WinTheme.text
        case .link: return WinTheme.blue
        case .quiet: return WinTheme.faint
        }
    }
}
