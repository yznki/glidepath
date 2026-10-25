import SwiftUI

/// The Linear row under Tending. The key lives in the login Keychain (`LinearKey`), never in config. Offscreen the field is
/// a plain well, and the status comes from the snapshot, so a snapshot never reads the Keychain.
struct LinearKeyRow: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store
    @Environment(\.offscreenRender) private var offscreen

    private var connected: Bool { store.snap.linearKey ?? model.linearSaved ?? false }
    private var typed: Bool { !model.linearDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        SettingItem(label: SettingsCopy.tendLinear.label, caption: SettingsCopy.tendLinear.caption,
                    error: model.rowErrors["linear"]) {
            HStack(spacing: 8) {
                if connected {
                    Text("Connected")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Gotham.mute)
                    SettingButton(title: "Remove") { model.removeLinearKey(store) }
                } else {
                    keyField
                    SettingButton(title: "Save", prominent: true, enabled: typed) { model.saveLinearKey(store) }
                }
            }
        }
    }

    @ViewBuilder private var keyField: some View {
        if offscreen {
            FieldStandIn(text: "", placeholder: "Linear API key", font: .system(size: 13, design: .monospaced),
                         height: 28, radius: 8)
                .frame(width: 200)
        } else {
            SecureField("Linear API key", text: $model.linearDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Gotham.fg)
                .padding(.horizontal, 10)
                .frame(width: 200, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Gotham.tint))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                .onSubmit { model.saveLinearKey(store) }
                .accessibilityLabel("Linear API key")
        }
    }
}
