import SwiftUI
import ServiceManagement
import AppKit

/// View-local state. SwiftUI's state wrappers are macros in the SDK and Command Line Tools cannot load
/// their plugins, so views keep their few mutable values in observable objects instead.
final class PopoverModel: ObservableObject {
    @Published var loginOn = false
    @Published var rowsHeight: CGFloat = 0
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

/// The header copy for each state (docs/design.md, section 2). Pure, so the copy is testable.
struct HeaderCopy: Equatable {
    enum Tone: Equatable {
        case ink, secondary, tertiary, changes, error
    }
    var headline: String
    var headlineTone: Tone = .ink
    var line2: String?
    var line2Tone: Tone = .ink
    var line2Weight: Int = 400
    var line3: String?
    var line3Tone: Tone = .secondary
    /// "Open log" follows line 3 as a link.
    var openLog = false

    static func make(_ kind: HeaderKind, now: Date) -> HeaderCopy {
        switch kind {
        case .notScheduled:
            return HeaderCopy(headline: "Not scheduled", headlineTone: .changes,
                              line2: "Run `glidepath init` to set it up")
        case .paused(let since, let lastStarted):
            let last = lastStarted.map { "Last sweep \(clock($0)) · scheduled sweeps skipped" }
                ?? "Scheduled sweeps are skipped"
            return HeaderCopy(headline: "Paused", line2: last,
                              line3: since.map { "Paused since \(clock($0))" }, line3Tone: .tertiary)
        case .running(let changes, let reviewing, let total, let landed, let started):
            var copy = HeaderCopy(headline: "Reviewing \(reviewing) of \(total)",
                                  line3: started.map { "Started \(clock($0))" }, line3Tone: .tertiary)
            if changes > 0 {
                copy.line2 = "\(changes) need changes"
                copy.line2Tone = .changes
                copy.line2Weight = 500
            } else {
                copy.line2 = "\(landed) landed"
            }
            return copy
        case .failed(let reason, let started, let next):
            let retry = next.map { "Retrying at \(clock($0)) · " } ?? ""
            _ = started
            return HeaderCopy(headline: "Last sweep failed", headlineTone: .error,
                              line2: reason, line3: retry, line3Tone: .tertiary, openLog: true)
        case .emptyRun(let repos, let next, let lastStarted):
            let last = lastStarted.map { " · last sweep \(clock($0))" } ?? ""
            return HeaderCopy(headline: "No open PRs",
                              line2: "Watching \(repos) repo\(repos == 1 ? "" : "s")\(last)",
                              line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" }, line3Tone: .tertiary)
        case .idle(let changes, let next, let lastStarted, let total):
            let count = "\(total) PR\(total == 1 ? "" : "s")"
            let last = lastStarted.map { "Last sweep \(clock($0)) · \(count)" } ?? count
            return HeaderCopy(headline: changes > 0 ? "\(changes) need changes" : "All clear",
                              line2: last,
                              line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" } ?? "No sweep scheduled",
                              line3Tone: .tertiary)
        case .noSweeps(let next, let repos):
            return HeaderCopy(headline: "Ready for the first sweep",
                              line2: "Reviews every open PR in \(repos) repo\(repos == 1 ? "" : "s")",
                              line3: next.map { "First sweep at \(clock($0))" }, line3Tone: .tertiary)
        }
    }

    /// Locale time: the user's format, 12 or 24 hour as the system has it.
    static func clock(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }

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

    /// Profile: full while running; the compact strip when idle, paused or failed with a last run; hidden when
    /// there is no run yet or no PR at all.
    private var showsProfile: Bool {
        if store.snap.running { return true }
        if store.snap.run == nil || store.snap.jobInstalled == false { return false }
        return !store.strips.isEmpty
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsProfile {
                ApproachProfile(marks: marks, mode: profileMode, compact: profileMode != .running,
                                hovered: store.hovered, justLanded: store.justLanded,
                                motion: store.profileMotion, onHover: { store.setHovered($0) })
                    .frame(width: Metrics.contentWidth,
                           height: profileMode == .running ? Metrics.profileFull : Metrics.profileCompact,
                           alignment: .topLeading)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                headerText(HeaderCopy.make(Presentation.headerKind(store.snap, now: context.date), now: context.date))
            }
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.top, Metrics.inset)
    }

    private func headerText(_ copy: HeaderCopy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(copy.headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tone(copy.headlineTone))
            if let line2 = copy.line2 {
                Text(line2)
                    .font(.system(size: 13, weight: copy.line2Weight == 500 ? .medium : .regular))
                    .foregroundStyle(tone(copy.line2Tone))
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            if copy.line3 != nil || copy.openLog {
                HStack(spacing: 0) {
                    if let line3 = copy.line3 {
                        Text(line3)
                            .font(.system(size: 12))
                            .foregroundStyle(tone(copy.line3Tone))
                    }
                    if copy.openLog {
                        openLogLink
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var openLogLink: some View {
        if offscreen {
            Text("Open log").font(.system(size: 13, weight: .medium)).foregroundStyle(p.error)
        } else {
            Button("Open log") { store.openLog() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.error)
        }
    }

    private func tone(_ t: HeaderCopy.Tone) -> Color {
        switch t {
        case .ink: return p.ink
        case .secondary: return p.secondary
        case .tertiary: return p.tertiary
        case .changes: return p.changesText
        case .error: return p.error
        }
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
        if store.snap.run == nil || groups.flatMap(\.rows).isEmpty {
            EmptyView()
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
                        .padding(.horizontal, Metrics.inset)
                }
                if groups.count > 1 {
                    Text(group.repo)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.secondary)
                        .padding(.horizontal, Metrics.inset)
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                } else {
                    Spacer().frame(height: 12)
                }
                if let error = group.error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(p.error)
                        .lineLimit(2)
                        .padding(.horizontal, Metrics.inset)
                        .padding(.bottom, 4)
                }
                ForEach(group.rows) { row in
                    PRRow(row: row, hovered: store.hovered == row.id, store: store, offscreen: offscreen)
                }
            }
        }
    }

    // MARK: Footer

    /// 12 pt above the footer row, 16 pt inset below it.
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
                    Button("Glidepath 1.0") {}
                        .disabled(true)
                    Divider()
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
        .padding(.horizontal, Metrics.inset)
        .padding(.top, 12)
        .padding(.bottom, Metrics.inset)
        .frame(height: 12 + Metrics.footerRow + Metrics.inset, alignment: .top)
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

/// One PR row (docs/design.md, section 4): a one-line title (or three lines with a reason), the meta line,
/// and the status idiom in a fixed 84 pt column. Heights are fixed: 44 pt or 60 pt.
struct PRRow: View {
    let row: RowModel
    let hovered: Bool
    let store: Store
    var offscreen = false
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var p: Palette { Palette(scheme) }
    private var strip: Strip { row.strip }

    private var height: CGFloat {
        if case .changes = row.status, strip.reason != nil { return Metrics.rowThreeLines }
        return Metrics.rowOneLine
    }

    var body: some View {
        Button {
            if let url = URL(string: "https://github.com/\(strip.repo)/pull/\(strip.number)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(strip.title ?? "Untitled PR")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // verbatim: a plain string, so PR numbers are never grouped as 1,212.
                    Text(verbatim: "#\(strip.number) · \(strip.author ?? "unknown")")
                        .font(.system(size: 12))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                    if case .changes = row.status, let reason = strip.reason {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(p.changesText)
                            .lineLimit(1)
                            .help(reason)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                statusColumn
                    .frame(width: Metrics.statusColumnWidth, alignment: .trailing)
                    .padding(.trailing, Metrics.chevronReserve)
            }
            .padding(.horizontal, Metrics.inset)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(p.ink.opacity(hovered ? 0.05 : 0))
                    .padding(.horizontal, 8)
            )
            .overlay(alignment: .trailing) {
                // Inside the reserved strip of the status column, so nothing moves on hover.
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(p.secondary.opacity(0.5))
                    .opacity(hovered ? 1 : 0)
                    .padding(.trailing, Metrics.inset)
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
        .onHover { inside in store.setHovered(inside ? strip.id : nil) }
    }

    @ViewBuilder
    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            switch row.status {
            case .changes:
                statusLine(.triangle, p.changesMark, "Changes", p.changesText)
            case .approved:
                statusLine(.disc, p.approveMark, "Approved", p.approveText)
            case .skipped:
                statusLine(.dash, p.skipMark, "Skipped", p.secondary)
            case .noResult:
                statusLine(.hollow, p.skipMark, "No result", p.secondary)
            case .active(let phase):
                statusLine(.hollow, p.doingMark, phase, p.doingText)
                if let meter = row.meter {
                    meterView(meter)
                }
            case .queued:
                statusLine(.hollow, p.skipMark, "Queued", p.secondary)
            }
        }
    }

    private func statusLine(_ shape: StatusShape, _ colour: Color, _ label: String, _ text: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(text)
                .lineLimit(1)
            StatusMark(shape: shape, colour: colour)
        }
    }

    /// Four dashes: done 35% ink, the current one the system blue, future 12% ink.
    private func meterView(_ segments: [MeterSegment]) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<segments.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(colour(segments[i]))
                    .frame(width: 9, height: 3)
            }
        }
    }

    private func colour(_ s: MeterSegment) -> Color {
        switch s {
        case .done: return p.meterDone
        case .current: return p.doingMark
        case .future: return p.meterFuture
        }
    }

    static func skippedText(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "Skipped" }
        return reason.prefix(1).uppercased() + reason.dropFirst() + ", skipped"
    }
}

/// The shapes of the status idiom and of the profile's marks.
enum StatusShape {
    case disc, hollow, triangle, dash
}

/// A 7 pt mark in a status shape.
struct StatusMark: View {
    let shape: StatusShape
    let colour: Color

    var body: some View {
        switch shape {
        case .disc:
            Circle().fill(colour).frame(width: 7, height: 7)
        case .hollow:
            Circle().strokeBorder(colour, lineWidth: 1.5).frame(width: 7, height: 7)
        case .triangle:
            Triangle().fill(colour).frame(width: 7, height: 7)
        case .dash:
            Capsule().fill(colour).frame(width: 7, height: 2.5)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
