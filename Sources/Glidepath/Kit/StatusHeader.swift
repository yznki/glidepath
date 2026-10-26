import SwiftUI

/// The top of the window and the popover: is it fine, and does it need me? A title (window only), the status sentence,
/// one trailing control, and the glide line. On a problem the control steps aside: the Fix button sits in the line's
/// gap instead.
struct StatusHeader<Control: View>: View {
    var title: String?
    let state: GlideState
    var size: GlideSize
    let onFix: () -> Void
    let control: Control

    /// `title` nil is the popover form: line on top, the sentence as the title.
    init(_ title: String? = nil, state: GlideState, size: GlideSize = .header, onFix: @escaping () -> Void,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.state = state
        self.size = size
        self.onFix = onFix
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: size == .header ? 6 : 10) {
            if title == nil { line }
            HStack(alignment: .center, spacing: 12) {
                if let title {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Ladder.title)
                        sentence.font(Ladder.secondary).foregroundStyle(.secondary)
                    }
                } else {
                    sentence.font(Ladder.title)
                }
                Spacer(minLength: 12)
                if !isProblem { control }
            }
            if title != nil { line }
        }
    }

    private var sentence: some View {
        Text(Copy.status(state)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
    }

    private var isProblem: Bool {
        if case .problem = state { return true }
        return false
    }

    private var line: some View {
        GlideLine(state, size: size) {
            if case .problem(_, let fix) = state {
                Button(action: onFix) {
                    Label(Copy.fix(fix), systemImage: "exclamationmark.triangle.fill")
                        .font(size == .header ? Ladder.action : Ladder.fine.weight(.semibold))
                        .padding(.horizontal, size == .header ? 12 : 8)
                        .padding(.vertical, size == .header ? 4 : 2)
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
            }
        }
    }
}
