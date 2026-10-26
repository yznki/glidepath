import SwiftUI

/// "Is it fine, and does it need me?" Rows only open the window; you decide there.
struct PopoverView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlideLine(compact: true)
                .padding(.horizontal, 10)
                .padding(.top, 10)
            HStack(alignment: .center, spacing: 12) {
                Text(store.status.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if store.lineMode != .problem {
                    Button(store.status.button) {
                        store.primary()
                        if store.status.button == "Open" { store.togglePopover() }
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)

            if !store.needsYou.isEmpty {
                VStack(spacing: 2) {
                    ForEach(store.needsYou.prefix(4)) { pr in
                        PopoverRow(pr: pr) {
                            store.open(pr.id)
                            store.togglePopover()
                        }
                    }
                    if store.needsCount > 4 {
                        Text("and \(store.needsCount - 4) more")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            if !store.since.isEmpty {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Since you last looked").font(.subheadline).foregroundStyle(.secondary)
                    Text(store.since).font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 16)
            HStack(spacing: 12) {
                Label(store.mode.rawValue, systemImage: store.mode == .autopilot ? "airplane" : "hand.raised")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                PauseMenu()
                    .fixedSize()
                Button {
                    store.openMain(); store.togglePopover()
                } label: {
                    Image(systemName: "macwindow")
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .help("Open Glidepath")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(Color.black.opacity(0.6).ignoresSafeArea())
    }
}

struct PopoverRow: View {
    let pr: PR
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(login: pr.author, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title).lineLimit(1)
                    NeedLine(pr: pr).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(.rect)
            .background(hover ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PauseMenu: View {
    @Environment(Store.self) private var store
    var body: some View {
        // Plain style so the label keeps full contrast; the system's glass menu button reads as disabled here.
        Menu {
            PauseItems()
        } label: {
            HStack(spacing: 4) {
                Text("Pause")
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct PauseItems: View {
    @Environment(Store.self) private var store
    var body: some View {
        if store.pausedUntil != nil {
            Button("Resume") { store.pausedUntil = nil }
            Divider()
        }
        Button("For 1 Hour") { store.pause("3:14 PM") }
        Button("For 3 Hours") { store.pause("5:14 PM") }
        Button("Until Tomorrow") { store.pause("tomorrow at 9:00 AM") }
        Button("Until Monday") { store.pause("Monday at 9:00 AM") }
    }
}
