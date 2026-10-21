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

/// Times the "Saved" stamp for a view model: `flash()` after each save, and `shown` is true for 2 s. A save during
/// those 2 s starts the count again.
@MainActor
final class SavedFlash: ObservableObject {
    @Published private(set) var shown = false
    private var count = 0

    func flash() {
        shown = true
        count += 1
        let mine = count
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.count == mine else { return }
            self.shown = false
        }
    }
}

/// The "Saved" word beside a title (12 faint). It fades in and out with `shown`.
struct SavedStamp: View {
    let shown: Bool

    var body: some View {
        Text("Saved")
            .font(.system(size: 12))
            .foregroundStyle(WinTheme.faint)
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: shown)
    }
}

/// One setting (base.css `.sec`): a 200 pt label column with a detail line, and the control column, with a rule above.
/// The label's first line is centred on a 32 pt control row. A message in `error` shows in amber under the control.
struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    var error: String?
    let control: Control

    init(title: String, detail: String, error: String?, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.error = error
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: WinMetrics.s24) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WinTheme.text)
                    .frame(height: 20, alignment: .leading)
                    .padding(.top, 6)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(width: 200, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                control
                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.amberInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, WinMetrics.s8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, WinMetrics.s16)
        .overlay(alignment: .top) {
            Rectangle().fill(WinTheme.line).frame(height: 1)
        }
    }
}

/// Set only by snapshot rendering. ImageRenderer draws ScrollView blank, so a snapshot draws the content inline.
private struct OffscreenRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var offscreenRender: Bool {
        get { self[OffscreenRenderKey.self] }
        set { self[OffscreenRenderKey.self] = newValue }
    }
}

/// A vertical scroll view. Offscreen (snapshots) it is the content itself, since ImageRenderer draws ScrollView blank.
struct WinScroll<Content: View>: View {
    @Environment(\.offscreenRender) private var offscreen
    @ViewBuilder let content: () -> Content

    var body: some View {
        if offscreen {
            // ScrollView content sits at the top; drawn inline it would centre in a full-height frame.
            // Taller than the frame, the content would centre its overflow. As an overlay on a view that takes only the
            // offered space, it reports no height of its own, so it stays at the top and is clipped to the frame.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    content().frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .clipped()
        } else {
            ScrollView { content() }
        }
    }
}
