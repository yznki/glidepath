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
}

private struct RowsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// "1.2k", "84k", "3.1M". Token counts in the menu.
func compactTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
    default: return "\(n)"
    }
}

/// The three header lines for each state (docs/design.md, section 2). Pure, so the copy is testable.
struct HeaderCopy: Equatable {
    enum Headline: Equatable {
        case ink(String)
        case dot(String)      // amber dot, then the text
        case error(String)
        case amber(String)
    }
    var headline: Headline
    var line2: String?
    var line3: String?
    var openLog = false

    static func make(_ kind: HeaderKind, now: Date) -> HeaderCopy {
        switch kind {
        case .notScheduled:
            return HeaderCopy(headline: .amber("Not scheduled"), line2: "Run `glidepath init` to set it up")
        case .paused(let since):
            return HeaderCopy(headline: .ink("Paused"), line2: "Scheduled sweeps are skipped",
                              line3: since.map { "Since \(clock($0))" })
        case .running(let changes, let reviewing, let total, let landed, let started):
            let headline: Headline = changes > 0 ? .dot("\(changes) need changes") : .ink("Reviewing \(total) PR\(total == 1 ? "" : "s")")
            return HeaderCopy(headline: headline,
                              line2: "\(reviewing) reviewing · \(landed) of \(total) landed",
                              line3: started.map { "Started \(clock($0))" })
        case .failed(_, let started):
            let from = started.map { " Showing results from \(clock($0))." } ?? ""
            return HeaderCopy(headline: .error("Last sweep failed"),
                              line2: "Couldn't finish the review.\(from)", openLog: true)
        case .emptyRun(let repos, let next):
            return HeaderCopy(headline: .ink("No open PRs"),
                              line2: "Watching \(repos) repo\(repos == 1 ? "" : "s")",
                              line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" })
        case .idle(let changes, let next, let lastStarted, let total):
            let headline: Headline = changes > 0 ? .dot("\(changes) need changes") : .ink("All clear")
            let count = "\(total) PR\(total == 1 ? "" : "s")"
            let last = lastStarted.map { "Last sweep \(clock($0)) · \(count)" } ?? count
            return HeaderCopy(headline: headline, line2: last,
                              line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" } ?? "No sweep scheduled")
        case .noSweeps(let next, let schedule):
            let times = schedule.map(\.text)
            let list: String
            switch times.count {
            case 0: list = "No schedule set"
            case 1: list = "A sweep runs at \(times[0])"
            default: list = "Sweeps run at \(times.dropLast().joined(separator: ", ")) and \(times.last ?? "")"
            }
            return HeaderCopy(headline: .ink("Ready for the first sweep"), line2: list,
                              line3: next.map { "Next at \(clock($0)), in \(untilText($0, now))" })
        }
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
        VStack(alignment: .leading, spacing: 12) {
            ApproachProfile(marks: marks, mode: profileMode, hovered: store.hovered,
                            justLanded: store.justLanded, motion: store.profileMotion,
                            onHover: { store.setHovered($0) })
                .frame(width: Metrics.contentWidth, height: Metrics.profileHeight, alignment: .topLeading)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                headerText(HeaderCopy.make(Presentation.headerKind(store.snap, now: context.date), now: context.date))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func headerText(_ copy: HeaderCopy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch copy.headline {
            case .ink(let s):
                Text(s).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
            case .dot(let s):
                HStack(spacing: 7) {
                    Circle().fill(p.amber).frame(width: 8, height: 8)
                    Text(s).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                }
            case .error(let s):
                Text(s).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.error)
            case .amber(let s):
                Text(s).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.changesChipText)
            }
            if let line2 = copy.line2 {
                Text(line2)
                    .font(.system(size: 13))
                    .foregroundStyle(p.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let line3 = copy.line3 {
                Text(line3)
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if copy.openLog {
                if offscreen {
                    Text("Open log").font(.system(size: 12)).foregroundStyle(p.error).underline()
                } else {
                    Button("Open log") { store.openLog() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .foregroundStyle(p.error)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileMode: ProfileMode {
        if store.snap.running { return .running }
        if store.snap.paused { return .paused }
        if let run = store.snap.run, run.finished != nil, Presentation.failureMessage(run) != nil { return .failed }
        return .idle
    }

    private var groups: [RepoGroup] {
        Presentation.rows(from: store.strips, running: store.snap.running, repos: store.snap.run?.repos ?? [])
    }

    private var marks: [ProfileMark] {
        Presentation.marks(groups, running: store.snap.running)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let groups = self.groups
        let rows = groups.flatMap(\.rows)
        if !store.snap.jobInstalled || (store.snap.run == nil && !store.snap.running) {
            Text(store.snap.jobInstalled ? "Nothing has run yet." : "Run glidepath init to set up the schedule.")
                .font(.system(size: 13))
                .foregroundStyle(p.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 8)
        } else if rows.isEmpty {
            EmptyView()   // the header already says "No open PRs"
        } else if offscreen {
            groupsView(groups)
        } else {
            ScrollView {
                groupsView(groups)
                    .background(GeometryReader { Color.clear.preference(key: RowsHeight.self, value: $0.size.height) })
            }
            .frame(height: min(max(local.rowsHeight, 1), Metrics.maxVisibleHeight))
            .onPreferenceChange(RowsHeight.self) { local.rowsHeight = $0 }
        }
    }

    private func groupsView(_ groups: [RepoGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Rectangle().fill(p.rule).frame(height: 1)
                        .padding(.horizontal, Metrics.gutter)
                }
                if groups.count > 1 {
                    Text(group.repo)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.secondary)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, index == 0 ? 14 : 20)
                        .padding(.bottom, 4)
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
        }
        .padding(.bottom, 4)
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
                    if let tokens = store.snap.run?.tokens, tokens > 0 {
                        Divider()
                        Button("Last run: \(compactTokens(tokens)) tokens") {}
                            .disabled(true)
                    }
                    Divider()
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
            standIn(store.snap.running ? "Stop" : (store.snap.paused ? "Resume" : "Run now"))
        } else if store.snap.running {
            Button("Stop") { confirmAndStop() }
                .buttonStyle(.bordered)
                .controlSize(.small)
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

    private func confirmAndStop() {
        let alert = NSAlert()
        alert.messageText = "Stop the current sweep?"
        alert.informativeText = "Reviews already posted stay posted."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Keep running")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.stopRun()
    }
}

/// One PR row: a title that wraps to two lines, meta, and the status column on the right (docs/design.md,
/// sections 3 and 4). Chevron on hover in the right gutter.
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(strip.title ?? "Untitled PR")
                        .font(.system(size: 13, weight: .semibold))
                        .lineSpacing(3)
                        .foregroundStyle(p.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    meta
                    if case .changes = row.status, let reason = strip.reason {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(p.changesChipText)
                            .lineLimit(1)
                            .help(reason)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                statusColumn
                    .padding(.trailing, hovered ? 14 : 0)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 9)
            .frame(minHeight: Metrics.rowMinHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(p.ink.opacity(hovered ? 0.05 : 0))
                    .padding(.horizontal, 8)
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(p.secondary)
                    .opacity(hovered ? 1 : 0)
                    .padding(.trailing, Metrics.gutter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(p.doingMark, lineWidth: 2)
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
        var rest = AttributedString(" · \(strip.author ?? "unknown")")
        rest.font = .system(size: 12)
        rest.foregroundColor = p.secondary
        return Text(line + rest).lineLimit(1)
    }

    @ViewBuilder
    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            switch row.status {
            case .changes:
                chip("Changes", text: p.changesChipText, fill: p.changesChipFill)
            case .approved:
                chip("Approved", text: p.approveChipText, fill: p.approveChipFill)
            case .noResult:
                chip("No result", text: p.noResultText, fill: p.noResultFill)
            case .skipped(let reason):
                Text(Self.skippedText(reason))
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
            case .active(let phase):
                Text(phase)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.doingText)
            case .queued:
                Text("Queued")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            }
            if let meter = row.meter {
                meterView(meter)
            }
        }
    }

    private func chip(_ label: String, text: Color, fill: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 8)
            .frame(height: Metrics.chipHeight)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill))
    }

    private func meterView(_ segments: [MeterSegment]) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<segments.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(colour(segments[i]))
                    .frame(width: 10, height: 3)
            }
        }
    }

    private func colour(_ s: MeterSegment) -> Color {
        switch s {
        case .done: return p.ink.opacity(0.6)
        case .current: return p.doingMark
        case .future: return p.meterFuture
        }
    }

    static func skippedText(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "Skipped" }
        return reason.prefix(1).uppercased() + reason.dropFirst() + ", skipped"
    }
}
