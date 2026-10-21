import SwiftUI
import ServiceManagement
import AppKit

/// View-local state. SwiftUI's state wrappers are macros in the SDK and Command Line Tools cannot load
/// their plugins, so views keep their few mutable values in observable objects instead.
final class PopoverModel: ObservableObject {
    @Published var loginOn = false
    @Published var rowsHeight: CGFloat = 0
}

final class SettleModel: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var angle: Double = 0
}

private struct RowsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// "1.2k", "84k", "3.1M". Token counts in the header.
func compactTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
    default: return "\(n)"
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    /// True only for snapshot rendering: ImageRenderer draws ScrollView and AppKit-backed controls blank.
    var offscreen = false
    @StateObject private var local = PopoverModel()
    @Environment(\.colorScheme) private var scheme

    private var p: Palette { Palette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(p.line).frame(height: 1)
            list
            footer
        }
        .frame(width: Metrics.popoverWidth)
        .background(offscreen ? p.ground : Color.clear)
        .onAppear {
            guard !offscreen else { return }
            store.popoverOpened()
            local.loginOn = store.loginItemOn
        }
        .onDisappear {
            guard !offscreen else { return }
            store.popoverClosed()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RadarView(blips: blips, mode: radarMode, hovered: store.hovered, motion: store.motion,
                      onHover: { store.setHovered($0) })
                .frame(width: Metrics.radar, height: Metrics.radar)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let kind = Presentation.headerKind(store.snap, now: context.date)
                headerText(kind, now: context.date)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 16)
    }

    private func headerText(_ kind: HeaderKind, now: Date) -> some View {
        let copy = HeaderCopy.make(kind, now: now, palette: p)
        return VStack(alignment: .leading, spacing: 4) {
            Text(copy.headline)
                .font(.system(size: 17, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let sub = copy.sub {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if copy.openLog {
                if offscreen {
                    Text("Open log").font(.system(size: 12)).foregroundStyle(p.doing)
                } else {
                    Button("Open log") { store.openLog() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.radar, alignment: .leading)
    }

    private var radarMode: RadarMode {
        if store.snap.running { return .running }
        if store.snap.paused { return .paused }
        return .idle
    }

    private var groups: [RepoGroup] {
        Presentation.rows(from: store.strips, running: store.snap.running, repos: store.snap.run?.repos ?? [])
    }

    /// Blips in display order: the radar's slot for a PR is its place in the list.
    private var blips: [Blip] {
        groups.flatMap(\.rows).map { row in
            Blip(id: row.id, progress: Presentation.progress(row.strip), verdict: row.strip.verdict,
                 active: row.strip.active && row.strip.verdict == nil)
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let groups = self.groups
        let rows = groups.flatMap(\.rows)
        if !store.snap.jobInstalled || (store.snap.run == nil && !store.snap.running) {
            Text(store.snap.jobInstalled ? "Nothing has run yet." : "Run glidepath init to set up the schedule.")
                .font(.system(size: 12))
                .foregroundStyle(p.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .frame(height: 52, alignment: .center)
        } else if rows.isEmpty {
            Text(groups.map(\.repo).joined(separator: ", ") + ": no open PRs")
                .font(.system(size: 12))
                .foregroundStyle(p.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .frame(height: 52, alignment: .center)
        } else if offscreen {
            groupsView(groups)
        } else {
            ScrollView {
                groupsView(groups)
                    .background(GeometryReader { Color.clear.preference(key: RowsHeight.self, value: $0.size.height) })
            }
            .frame(height: min(max(local.rowsHeight, 1), CGFloat(Metrics.maxVisibleRows) * Metrics.rowPitch + 40))
            .onPreferenceChange(RowsHeight.self) { local.rowsHeight = $0 }
        }
    }

    private func groupsView(_ groups: [RepoGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    if groups.count > 1 {
                        Text(group.repo)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(p.secondary)
                            .padding(.horizontal, Metrics.gutter)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                    }
                    if let error = group.error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(p.error)
                            .lineLimit(2)
                            .padding(.horizontal, Metrics.gutter)
                            .padding(.bottom, 4)
                    }
                    ForEach(group.rows) { row in
                        PRRow(row: row, hovered: store.hovered == row.id, store: store, offscreen: offscreen)
                    }
                }
                .padding(.bottom, groups.count > 1 ? 4 : 0)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton
            Spacer(minLength: 0)
            if offscreen {
                // ImageRenderer draws AppKit menus as a prohibition sign; the symbol stands in for the menu.
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(p.ink)
            } else {
            Menu {
                Button(store.snap.paused ? "Resume" : "Pause") { store.togglePause() }
                Button("Open log") { store.openLog() }
                Toggle("Open at login", isOn: Binding(
                    get: { local.loginOn },
                    set: { on in
                        store.setLoginItem(on)
                        local.loginOn = store.loginItemOn
                    }
                ))
                Divider()
                Button("Quit Glidepath") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(p.ink)
                    .accessibilityLabel("More")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(height: Metrics.footer)
    }

    /// The bordered button, drawn in SwiftUI when rendering offscreen. Same size and outline.
    private func standIn(_ label: String, enabled: Bool = true) -> some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(p.ink.opacity(enabled ? 1 : 0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(p.ink.opacity(0.22), lineWidth: 1))
    }

    @ViewBuilder
    private var footerButton: some View {
        if offscreen {
            standIn(store.snap.running ? "Running…" : (store.snap.paused ? "Resume" : "Run now"),
                    enabled: !store.snap.running)
        } else if store.snap.running {
            Button("Running…") {}
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
        } else if store.snap.paused {
            Button("Resume") { store.togglePause() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            Button("Run now") { confirmAndRun() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!store.snap.jobInstalled)
        }
    }

    /// Posting is public, so a run that can post reviews asks first.
    private func confirmAndRun() {
        if store.snap.postsReviews {
            let alert = NSAlert()
            alert.messageText = "Run the review pipeline now?"
            alert.informativeText = "Some repos post reviews with posting = \"review\", which show as real reviews on GitHub."
            alert.addButton(withTitle: "Run now")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        store.runNow()
    }
}

/// Header copy for each HeaderKind (docs/design.md, header table).
struct HeaderCopy {
    var headline: AttributedString
    var sub: String?
    var openLog = false

    static func make(_ kind: HeaderKind, now: Date, palette p: Palette) -> HeaderCopy {
        switch kind {
        case .notScheduled:
            return HeaderCopy(headline: text("Not scheduled", p.changesText),
                              sub: "Run `glidepath init` to set it up")
        case .paused(let since):
            return HeaderCopy(headline: text("Paused", p.ink),
                              sub: since.map { "Since \(clock($0)) · scheduled sweeps are skipped" }
                                ?? "Scheduled sweeps are skipped")
        case .running(let changes, let reviewing, let total, let landed, let started, let tokens):
            let headline = changes > 0
                ? text("\(changes) need changes\u{00A0}·", p.changesText) + text(" \(reviewing) reviewing", p.ink)
                : text("Reviewing \(total) PR\(total == 1 ? "" : "s")", p.ink)
            var parts = ["\(landed) of \(total) landed"]
            if let started { parts.append("started \(clock(started))") }
            if tokens > 0 { parts.append("\(compactTokens(tokens)) tokens") }
            return HeaderCopy(headline: headline, sub: parts.joined(separator: " · "))
        case .failed(let message):
            return HeaderCopy(headline: text("Last sweep failed", p.error), sub: message, openLog: true)
        case .emptyRun(let repos, let checkedAt, let next):
            var sub = "Checked \(repos) repo\(repos == 1 ? "" : "s") at \(clock(checkedAt))"
            if let next { sub += " · next \(clock(next))" }
            return HeaderCopy(headline: text("No PRs to review", p.ink), sub: sub)
        case .idle(let changes, let next):
            let headline = changes > 0
                ? text("\(changes) need changes", p.changesText)
                : text("All clear", p.ink)
            return HeaderCopy(headline: headline, sub: next.map { "Next sweep \(clock($0)) · in \(untilText($0, now))" }
                              ?? "No sweep scheduled")
        case .noSweeps(let next):
            return HeaderCopy(headline: text("No sweeps yet", p.ink),
                              sub: next.map { "First sweep \(clock($0)) · in \(untilText($0, now))" }
                                ?? "No schedule set")
        }
    }

    static func text(_ s: String, _ colour: Color) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = colour
        return a
    }

    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ d: Date) -> String { clockFormatter.string(from: d) }

    static func untilText(_ next: Date, _ now: Date) -> String {
        let mins = max(0, Int(next.timeIntervalSince(now) / 60))
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}

/// One PR row: 52 pt pitch, title and meta on the left, a fixed 72 pt right column.
struct PRRow: View {
    let row: RowModel
    let hovered: Bool
    let store: Store
    var offscreen = false
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var p: Palette { Palette(scheme) }
    private var strip: Strip { row.strip }

    var body: some View {
        Button {
            if let url = URL(string: "https://github.com/\(strip.repo)/pull/\(strip.number)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(strip.title ?? "Untitled PR")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rightColumn
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(p.secondary)
                    .opacity(hovered ? 1 : 0)
                    .frame(width: 11)
            }
            .padding(.horizontal, Metrics.gutter)
            .frame(height: Metrics.rowPitch)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(p.ink.opacity(hovered ? 0.05 : 0))
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(p.doing, lineWidth: 2)
                .padding(.horizontal, 8)
                .opacity(focused ? 1 : 0)
        )
        .help(strip.reason ?? "")
        .onHover { inside in store.setHovered(inside ? strip.id : nil) }
    }

    private var meta: some View {
        var line = AttributedString("#\(strip.number)")
        line.font = .system(size: 12, design: .monospaced)
        line.foregroundColor = p.secondary
        var rest = AttributedString(" · \(strip.author ?? "unknown")" + (strip.reason.map { " · \($0)" } ?? ""))
        rest.font = .system(size: 12)
        rest.foregroundColor = p.secondary
        return Text(line + rest).lineLimit(1)
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let verdict = strip.verdict {
                Stamp(verdict: verdict, settle: store.justLanded.contains(strip.id), offscreen: offscreen)
            } else if let phase = row.phase {
                Text(phase)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.doing)
            }
            if let rail = row.rail {
                RailView(segments: rail, palette: p)
            }
        }
        .frame(width: Metrics.rightColumn, alignment: .trailing)
    }
}

/// The four-part rail: done segments ink at 60%, the current segment in the doing colour, future at 12%.
struct RailView: View {
    let segments: [RailSegment]
    let palette: Palette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments.count, id: \.self) { i in
                Capsule()
                    .fill(colour(segments[i]))
                    .frame(width: (Metrics.railWidth - 9) / 4, height: 3)
            }
        }
        .frame(width: Metrics.railWidth, height: 3)
    }

    private func colour(_ s: RailSegment) -> Color {
        switch s {
        case .done: return palette.ink.opacity(0.6)
        case .current: return palette.doing
        case .future: return palette.ink.opacity(0.12)
        }
    }
}

/// A verdict stamp: upright at rest, 72 pt wide. It settles into place once when it lands on an open popover.
struct Stamp: View {
    let verdict: Verdict
    let settle: Bool
    var offscreen = false
    @StateObject private var model = SettleModel()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = Palette(scheme)
        let word: String = {
            switch verdict {
            case .approve: return "APPROVED"
            case .changes: return "CHANGES"
            case .skipped: return "SKIPPED"
            }
        }()
        Text(word)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(p.verdictText(verdict))
            .frame(width: Metrics.rightColumn)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(p.verdictFill(verdict).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(p.verdictText(verdict), lineWidth: 1.5))
            .scaleEffect(model.scale)
            .rotationEffect(.degrees(model.angle))
            .onAppear {
                guard settle, !offscreen, !reduceMotion else { return }
                model.scale = 1.15
                model.angle = -3
                withAnimation(.easeOut(duration: 0.14)) {
                    model.scale = 1
                    model.angle = 0
                }
            }
    }
}
