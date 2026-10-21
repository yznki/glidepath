import SwiftUI

/// The ⌘/ sheet: every shortcut in the table, grouped like the menus, in two columns, with a search field on top.
/// Settings' row pattern: the name on the left, the keys on the right. Esc closes it.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ShortcutsModel()
    @Environment(\.offscreenRender) private var offscreen

    var body: some View {
        let groups = Shortcuts.filter(model.query)
        let split = Shortcuts.columns(groups)
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(WinTheme.text)
            // Snapshot rendering draws AppKit text fields as placeholders, so it gets a stand-in with the same look.
            Group {
                if offscreen {
                    Text(model.query.isEmpty ? "Search shortcuts" : model.query)
                        .font(.system(size: 13))
                        .foregroundStyle(WinTheme.faint)
                        .padding(.horizontal, WinMetrics.s12)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(WinTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WinTheme.control, lineWidth: 1))
                } else {
                    TextField("Search shortcuts", text: $model.query)
                        .winField()
                }
            }
            .padding(.top, WinMetrics.s16)
            // WinScroll, not ScrollView: snapshot rendering draws ScrollView blank.
            WinScroll {
                if groups.isEmpty {
                    Text("No shortcuts match \"\(model.query)\".")
                        .font(.system(size: 13))
                        .foregroundStyle(WinTheme.muted)
                        .padding(.top, WinMetrics.s24)
                } else {
                    HStack(alignment: .top, spacing: WinMetrics.s32) {
                        column(split.left)
                        column(split.right)
                    }
                    .padding(.top, WinMetrics.s8)
                }
            }
            HStack {
                Spacer()
                WinButton(title: "Done", style: .primary) { dismiss() }
            }
            .padding(.top, WinMetrics.s16)
        }
        .padding(.horizontal, WinMetrics.s24)
        .padding(.top, 48)
        .padding(.bottom, WinMetrics.s24)
        .frame(width: 640, height: 720, alignment: .topLeading)
        .background(WinTheme.ground)
        .onExitCommand { dismiss() }
    }

    private func column(_ groups: [(title: String, items: [Shortcut])]) -> some View {
        VStack(alignment: .leading, spacing: WinMetrics.s20) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WinTheme.faint)
                        .padding(.bottom, WinMetrics.s8)
                    ForEach(group.items) { item in
                        HStack(spacing: WinMetrics.s12) {
                            Text(item.title)
                                .font(.system(size: 13))
                                .foregroundStyle(WinTheme.text)
                            Spacer(minLength: WinMetrics.s8)
                            Text(item.glyphs)
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(WinTheme.muted)
                        }
                        .frame(height: 28)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(WinTheme.line).frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

final class ShortcutsModel: ObservableObject {
    @Published var query = ""
}
