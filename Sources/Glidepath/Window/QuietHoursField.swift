import SwiftUI

/// The quiet hours as text, such as "22:00-07:00,sat,sun". The text is committed on Enter, and a value that does not
/// read is refused by the save and shown under the row. Offscreen it is a plain well with the same text.
struct QuietHoursField: View {
    /// The saved text. The field follows it when it changes.
    let text: String
    let offscreen: Bool
    let onCommit: (String) -> Void

    final class Entry: ObservableObject { @Published var text = "" }
    @StateObject private var entry = Entry()

    var body: some View {
        Group {
            if offscreen {
                FieldStandIn(text: text, placeholder: "22:00-07:00,sat,sun", font: .system(size: 13, design: .monospaced),
                             height: 28, radius: 8)
                    .frame(width: 200)
            } else {
                TextField("22:00-07:00,sat,sun", text: $entry.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Gotham.fg)
                    .padding(.horizontal, 10)
                    .frame(width: 200, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Gotham.tint))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                    .onSubmit {
                        let value = entry.text.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { return }
                        onCommit(value)
                    }
                    .onAppear { entry.text = text }
                    .onChange(of: text) { _, now in entry.text = now }
                    .accessibilityLabel("Quiet hours")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
