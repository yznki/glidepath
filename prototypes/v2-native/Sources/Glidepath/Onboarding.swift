import SwiftUI

struct Onboarding: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var ghReady = false
    @State private var picked: [String: Bool] = ["lumen/web": true, "lumen/api": true, "SagerDrone/Sager": true, "yznki/glidepath": false]
    @State private var reviewTeam = true
    @State private var lookAfterMine = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text(title).font(.title.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .padding(.horizontal, 40)

            Form { content }
                .formStyle(.grouped)
                .scrollDisabled(true)

            HStack {
                Text("Step \(step) of 3").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if step > 1 && step < 3 { Button("Back") { withAnimation { step -= 1 } } }
                if step == 3 {
                    Button("Later") { dismiss() }
                    Button("Check Now") { dismiss(); store.checkNow() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                } else {
                    Button("Continue") { withAnimation { step += 1 } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                        .disabled(step == 1 && !ghReady)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: step == 2 ? 560 : 440)
    }

    private var icon: String { ["wrench.and.screwdriver", "books.vertical", "checkmark.circle"][step - 1] }
    private var title: String { ["One thing to fix", "Pick your repos", "You're set"][step - 1] }
    private var subtitle: String {
        [
            "Glidepath uses Claude Code, Git and the GitHub CLI on this Mac.",
            "Glidepath checks these repos on a schedule. You can change this any time in Repos.",
            "Glidepath will check at 9:00, 1:00 and 5:00 and ask before posting anything.",
        ][step - 1]
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 1:
            Section {
                tool("Claude Code", ok: true)
                tool("Git", ok: true)
                LabeledContent {
                    if ghReady {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else {
                        Button("Sign In…") { withAnimation { ghReady = true } }
                    }
                } label: {
                    Text("GitHub CLI")
                    Text(ghReady ? "Signed in as yznki" : "Installed, but not signed in to GitHub.")
                }
            }
        case 2:
            Section {
                ForEach(picked.keys.sorted(), id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { picked[name] ?? false }, set: { picked[name] = $0 }))
                }
            }
            Section {
                Toggle("Review my team's PRs", isOn: $reviewTeam)
                Toggle("Look after my own PRs", isOn: $lookAfterMine)
            }
        default:
            Section {
                LabeledContent("Repos", value: "\(picked.values.filter { $0 }.count)")
                LabeledContent("Checks", value: "Weekdays at 9:00, 1:00 and 5:00")
                LabeledContent("Before posting", value: "Asks you first")
            } footer: {
                Text("Check now is a real check. Nothing reaches GitHub without you; results land in your Inbox.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tool(_ name: String, ok: Bool) -> some View {
        LabeledContent(name) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
        }
    }
}
