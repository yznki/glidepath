import SwiftUI

/// Settings controls in the Gotham look: rows, groups, switches, segments, sliders, tags, keycap, ring, drawer, toast.

// MARK: Rows and groups

/// One row: label and caption on the left, the control on the right (or under the label when `stacked`). Its error, if
/// any, sits under the row. A hairline separates it from the row above.
struct SettingItem<Control: View>: View {
    let label: String
    var caption: String = ""
    var error: String?
    var stacked = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if stacked {
                labelBlock
                control()
            } else {
                HStack(alignment: .center, spacing: 14) {
                    labelBlock
                    Spacer(minLength: 12)
                    control()
                }
            }
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Gotham.edge).frame(height: 1) }
    }

    private var labelBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Gotham.fg)
                .fixedSize(horizontal: false, vertical: true)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A group card: the cap title above a rounded glass-tinted list of rows. `id` is the scroll target for the chips.
struct SettingGroup<Content: View>: View {
    let id: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .cap()
                .padding(.leading, 4)
                .padding(.top, 22)
                .padding(.bottom, 9)
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Gotham.row))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
        }
        .id(id)
    }
}

// MARK: Controls

/// The on/off switch: a 44 x 26 capsule, filled in the foreground colour when on.
struct SettingSwitch: View {
    let isOn: Bool
    var label = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Gotham.fg : Gotham.edge)
                Circle()
                    .fill(isOn ? Gotham.void : Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.3), radius: 2.5, y: 2)
                    .padding(2)
            }
            .frame(width: 44, height: 26)
            .animation(.easeOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A row of options in one tray; the selected one is raised. Nothing is selected when `selected` is nil (mixed values).
struct SettingSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selected: Value?
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = selected == option.value
                Button { onSelect(option.value) } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(on ? Gotham.fg : Gotham.mute)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Gotham.tint : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Gotham.row))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
    }
}

/// Plain slider in the foreground colour, 170 pt wide, with the value text at its right.
struct SettingSliderTrack: View {
    @Environment(\.offscreenRender) private var offscreen
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var onEditing: (Bool) -> Void = { _ in }

    var body: some View {
        if offscreen {
            SliderStandIn(value: value, range: range)
        } else {
            Slider(value: $value, in: range, step: step, onEditingChanged: onEditing,
                   minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(), label: { EmptyView() })
                .tint(Gotham.fg)
                .frame(width: 170)
        }
    }
}

/// The slider drawn with Gotham tokens, for offscreen (snapshot) rendering: a thin track, the filled part and a knob at
/// the value. ImageRenderer draws the AppKit slider as a prohibition sign.
struct SliderStandIn: View {
    let value: Double
    let range: ClosedRange<Double>
    private let width: CGFloat = 170

    var body: some View {
        let span = range.upperBound - range.lowerBound
        let f = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
        ZStack(alignment: .leading) {
            Capsule().fill(Gotham.row).frame(width: width, height: 4)
            Capsule().fill(Gotham.fg).frame(width: width * CGFloat(f), height: 4)
            Circle().fill(Gotham.fg).frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(x: width * CGFloat(f) - 7)
        }
        .frame(width: width, height: 14, alignment: .leading)
    }
}

/// The value a slider row is showing while a drag is live. Owned by the row, so the config is written once on release.
final class SliderDraft: ObservableObject {
    @Published var value: Double?
}

/// A slider that writes the config only when the drag ends. While dragging, the label and caption follow the draft.
struct SettingSlider: View {
    @ObservedObject var draft: SliderDraft
    let committed: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let valueText: (Double) -> String
    let commit: (Double) -> Void

    var body: some View {
        let shown = draft.value ?? committed
        HStack(spacing: 12) {
            SettingSliderTrack(
                value: Binding(get: { shown }, set: { draft.value = $0 }),
                range: range, step: step,
                onEditing: { editing in
                    if !editing, let value = draft.value { commit(value) }
                })
            Text(valueText(shown))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Gotham.fg)
                .frame(minWidth: 96, alignment: .trailing)
        }
    }
}

/// Tags with a field for one more. Enter adds the field's text; each tag's ✕ removes it.
struct SettingTags: View {
    final class Entry: ObservableObject { @Published var text = "" }

    let tags: [String]
    let placeholder: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    @StateObject private var entry = Entry()
    @Environment(\.offscreenRender) private var offscreen

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 2) {
                    Text(tag)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Gotham.fg)
                    Button { onRemove(tag) } label: {
                        Text("✕")
                            .font(.system(size: 10))
                            .foregroundStyle(Gotham.mute)
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(tag)")
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(height: 26)
                .background(Capsule().fill(Gotham.tint))
                .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
            }
            if offscreen {
                FieldStandIn(text: "", placeholder: placeholder, font: .system(size: 12, design: .monospaced), height: 26, radius: 13)
                    .frame(width: 140)
            } else {
                TextField(placeholder, text: $entry.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Gotham.fg)
                    .padding(.horizontal, 10)
                    .frame(width: 140, height: 26)
                    .overlay(Capsule().strokeBorder(Gotham.edge, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .onSubmit {
                        let text = entry.text.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        entry.text = ""
                        onAdd(text)
                    }
                    .accessibilityLabel(placeholder)
            }
        }
    }
}

/// The shortcut as a keycap. Click to record; while recording it reads "Type shortcut" in the signal colour.
struct SettingKeycap: View {
    @AppStorage("signalColour") private var signalKey = "amber"
    let text: String
    let recording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(recording ? "Type shortcut" : text)
                .font(.system(size: recording ? 12 : 15, weight: .medium))
                .foregroundStyle(recording ? Gotham.signal(signalKey) : Gotham.fg)
                .frame(minWidth: 120, minHeight: 34)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Gotham.tint, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(recording ? Gotham.signal(signalKey) : Gotham.edge, lineWidth: recording ? 1.5 : 1))
                .shadow(color: .black.opacity(0.6), radius: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Glidepath shortcut, \(text)")
    }
}

/// A small outlined button. `prominent` fills it, as the one action on a row.
struct SettingButton: View {
    let title: String
    var prominent = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(prominent ? Gotham.void : Gotham.fg)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? Gotham.fg : Gotham.tint))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Gotham.edge, lineWidth: prominent ? 0 : 1))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The monthly budget as a ring: the share of the budget used this month. The ring turns the signal colour past 80 %.
/// Shows a dash when there is no budget.
struct BudgetRing: View {
    @AppStorage("signalColour") private var signalKey = "amber"
    let fraction: Double?

    var body: some View {
        let hot = (fraction ?? 0) > 0.8
        ZStack {
            Circle().stroke(Gotham.edge, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, fraction ?? 0)))
                .stroke(hot ? Gotham.signal(signalKey) : Gotham.fg, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            Text(fraction.map { "\(Int(min(1, $0) * 100))%" } ?? "–")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Gotham.fg)
        }
        .frame(width: 54, height: 54)
        .accessibilityLabel(fraction.map { "\(Int(min(1, $0) * 100)) percent of the monthly budget used" } ?? "No budget")
    }
}

/// The pale pill at the bottom of the pane.
struct SettingsToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: "0A0A0C"))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.95)))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}

// MARK: config.toml drawer

/// The config file as text, monospaced: section headers bold, keys muted, changed lines highlighted.
struct ConfigDrawer: View {
    let lines: [String]
    let changed: Set<Int>
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("config.toml").cap()
                Spacer()
                SettingButton(title: "Close", action: onClose)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        ConfigLine(text: line, changed: changed.contains(index))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: 400, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: "060608").opacity(0.92))
        .overlay(alignment: .leading) { Rectangle().fill(Gotham.edge).frame(width: 1) }
    }
}

/// One line of config.toml. A changed line fades its highlight out.
private struct ConfigLine: View {
    let text: String
    let changed: Bool

    var body: some View {
        content
            .font(.system(size: 12, design: .monospaced))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(changed ? 0.16 : 0)))
    }

    @ViewBuilder private var content: some View {
        if text.hasPrefix("[") {
            Text(text).fontWeight(.bold).foregroundStyle(Gotham.fg)
        } else if text.hasPrefix("#") {
            Text(text).foregroundStyle(Gotham.mute)
        } else if let split = text.range(of: " = ") {
            HStack(spacing: 0) {
                Text(String(text[..<split.lowerBound])).foregroundStyle(Gotham.mute)
                Text(String(text[split.lowerBound...])).foregroundStyle(Gotham.fg)
            }
        } else {
            Text(text.isEmpty ? " " : text).foregroundStyle(Gotham.fg)
        }
    }
}
