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
    /// A 32 pt primary, for a row's action; the default primary is 44 pt.
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(WinButtonStyle(style: style, large: large, small: small))
    }
}

/// The drawing behind `WinButton`. Reads `isEnabled`, so `.disabled` dims it.
private struct WinButtonStyle: ButtonStyle {
    let style: WinButton.Style
    let large: Bool
    let small: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var isLink: Bool { style == .link || style == .quiet }
    private var isBig: Bool { !small && (style == .primary || large) }

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

/// The custom pill segmented control (base.css `.seg`): a raised 32 pt track with a 3 pt inset and 26 pt pills.
/// The selected pill takes the active fill and a 1 pt ring. Used for the Reviews filter, and for Repos and Schedule.
struct WinSegmented<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: String
    }

    let segments: [Segment]
    let selected: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let on = segment.value == selected
                Button {
                    onSelect(segment.value)
                } label: {
                    Text(segment.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? WinTheme.text : WinTheme.muted)
                        .lineLimit(1)
                        .padding(.horizontal, WinMetrics.s12)
                        .frame(height: 26)
                        .background(Capsule().fill(on ? WinTheme.active : Color.clear))
                        .overlay(Capsule().strokeBorder(on ? WinTheme.segRing : Color.clear, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(Capsule().fill(WinTheme.raised))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A verdict's mark and word in the fixed 88 pt status column (base.css `.st`): an amber triangle for changes,
/// a green dot for approve, and a faint dash for skipped and too large.
struct WinStatus: View {
    enum Kind {
        case changes, approved, skipped, tooLarge
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: WinMetrics.s8) {
            switch kind {
            case .changes:
                Text("Changes").foregroundStyle(WinTheme.amberInk)
                StatusTriangle().fill(WinTheme.amber).frame(width: 8, height: 7)
            case .approved:
                Text("Approve").foregroundStyle(WinTheme.green)
                Circle().fill(WinTheme.green).frame(width: 7, height: 7)
            case .skipped:
                Text("Skipped").foregroundStyle(WinTheme.faint)
                Rectangle().fill(WinTheme.faint).frame(width: 8, height: 2)
            case .tooLarge:
                Text("Too large").foregroundStyle(WinTheme.faint)
                Rectangle().fill(WinTheme.faint).frame(width: 8, height: 2)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .frame(width: 88, alignment: .trailing)
    }
}

/// The status triangle: 8 wide, 7 high, pointing up.
struct StatusTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The on/off switch (base.css `.toggle`): 32 by 20, green when on, the control stroke when off, a white knob.
struct WinToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? WinTheme.green : WinTheme.control)
                Circle().fill(Color.white).frame(width: 16, height: 16).padding(2)
            }
            .frame(width: 32, height: 20)
            .animation(.easeOut(duration: 0.14), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
