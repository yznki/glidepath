import SwiftUI
import ServiceManagement
import AppKit

/// View-local state. SwiftUI's state wrappers are macros in the SDK and Command Line Tools cannot load
/// their plugins, so views keep their few mutable values in observable objects instead.
final class PopoverModel: ObservableObject {
    @Published var loginOn = false
    @Published var rowsHeight: CGFloat = 0
    @Published var headerHeight: CGFloat = 0
}

private struct HeaderHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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

    /// `drafts` is the number of reviews waiting to be posted. Idle copy gives way to that count when it is not zero.
    static func make(_ kind: HeaderKind, now: Date, drafts: Int = 0) -> HeaderCopy {
        switch kind {
        case .notScheduled:
            return HeaderCopy(headline: "Not scheduled", headlineTone: .changes,
                              line2: "Run `glidepath init` to set it up")
        case .paused(let since, let lastStarted):
            let last = lastStarted.map { "Last sweep \(clock($0)) · scheduled sweeps skipped" }
                ?? "Scheduled sweeps are skipped"
            return HeaderCopy(headline: "Paused", headlineTone: .changes, line2: last,
                              line3: since.map { "Paused since \(clock($0))" }, line3Tone: .tertiary)
        case .running(let changes, let inFlight, _, let landed, let started):
            var copy = HeaderCopy(headline: "\(inFlight) in flight, \(landed) landed",
                                  line3: started.map { "Started \(clock($0))" }, line3Tone: .tertiary)
            if changes > 0 {
                copy.line2 = "\(changes) need changes"
                copy.line2Tone = .changes
                copy.line2Weight = 500
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
            var copy = HeaderCopy(headline: changes > 0 ? "\(changes) need changes" : "All clear",
                                  line2: last,
                                  line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" } ?? "No sweep scheduled",
                                  line3Tone: .tertiary)
            if drafts > 0 {
                copy.line2 = "\(drafts) draft\(drafts == 1 ? "" : "s") to post"
                copy.line2Weight = 500
            }
            return copy
        case .dryRun:
            return HeaderCopy(headline: "Dry run in progress", line2: "Nothing is posted. Watch it in Glidepath.",
                              line2Tone: .secondary)
        case .notConfigured(let next):
            return HeaderCopy(headline: "Ready for the first sweep",
                              line2: "Pick the repos Glidepath should review.",
                              line3: next.map { "First sweep at \(clock($0))" }, line3Tone: .tertiary)
        case .noSweeps(let next, let repos):
            return HeaderCopy(headline: "Ready for the first sweep",
                              line2: "Watching \(repos) repo\(repos == 1 ? "" : "s")",
                              line3: next.map { "First sweep at \(clock($0)), in \(untilText($0, now))" }
                                  ?? "No sweep scheduled",
                              line3Tone: .tertiary)
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
    /// Snapshot time for the profile's motion. nil uses the live clock.
    var clock: Date?
    @StateObject private var local = PopoverModel()
    @Environment(\.colorScheme) private var scheme

    private var p: Palette { Palette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
            updateLine
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
                            justLanded: store.justLanded, motion: store.profileMotion, clock: clock,
                            onHover: { store.setHovered($0) })
            TimelineView(.periodic(from: .now, by: 30)) { context in
                headerText(HeaderCopy.make(Presentation.headerKind(store.snap, now: context.date), now: context.date,
                                           drafts: store.draftCount))
            }
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.top, Metrics.inset)
        .background(GeometryReader { Color.clear.preference(key: HeaderHeight.self, value: $0.size.height) })
        .onPreferenceChange(HeaderHeight.self) { local.headerHeight = $0 }
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
        if store.snap.run == nil || !store.snap.jobInstalled || store.strips.isEmpty { return .empty }
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
            // Header and footer take their own height; the list gets what is left under the 640 pt cap.
            .frame(height: min(max(local.rowsHeight, 1),
                               max(Metrics.popoverMaxHeight - local.headerHeight - Metrics.footerRow - 24, 1)))
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
                // A heading only over rows: a repo with nothing to show gets no empty heading. Its error, if any, leads with
                // the repo name instead.
                let heading = groups.count > 1 && !group.rows.isEmpty
                if heading {
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
                    Text(groups.count > 1 && !heading ? "\(group.repo): \(error)" : error)
                        .font(.system(size: 12))
                        .foregroundStyle(p.error)
                        .lineLimit(2)
                        .padding(.horizontal, Metrics.inset)
                        .padding(.bottom, 4)
                }
                ForEach(group.rows) { row in
                    PRRow(row: row, hovered: store.hovered == row.id, store: store,
                          dimmed: store.snap.paused, offscreen: offscreen)
                }
            }
        }
    }

    // MARK: Update

    /// One line above the footer: an update on offer, its progress or failure, or the result of "Check for updates…".
    @ViewBuilder
    private var updateLine: some View {
        if store.snap.updatePhase == .updating, let update = store.availableUpdate {
            updateRow {
                HStack(spacing: 6) {
                    if offscreen {
                        // ImageRenderer draws ProgressView as a prohibition sign; a symbol stands in for it.
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Updating to \(update.latest)…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.secondary)
                }
            }
        } else if store.snap.updatePhase == .failed {
            updateRow {
                HStack(spacing: 0) {
                    Text("Update failed · ")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.error)
                    openLogLink
                }
            }
        } else if let note = store.snap.updateNote {
            updateRow {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            }
        } else if store.snap.updateChecking {
            updateRow {
                Text("Checking for updates…")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            }
        } else if let update = store.availableUpdate {
            updateRow {
                HStack(spacing: 0) {
                    Text("Glidepath \(update.latest) is available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.ink)
                    Spacer(minLength: 8)
                    linkButton("What's new") {
                        if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
                    }
                    linkButton("Update") { confirmAndUpdate(update) }
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func updateRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 12)
    }

    @ViewBuilder
    private func linkButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        if offscreen {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(p.doingText)
        } else {
            Button(label, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.doingText)
        }
    }

    // MARK: Footer

    /// 12 pt above the footer row and 12 pt below it: the popover ends where the buttons end.
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
                    Button("Open Glidepath") { WindowRouter.shared.open(.overview) }
                    Divider()
                    if let update = store.availableUpdate {
                        Button("Update to \(update.latest)…") { confirmAndUpdate(update) }
                            .disabled(store.snap.updatePhase == .updating)
                    } else {
                        Button("Glidepath \(Version.current)") {}
                            .disabled(true)
                    }
                    Divider()
                    Button(store.snap.paused ? "Resume" : "Pause") { store.togglePause() }
                    Button("Open log") { store.openLog() }
                    Button("Reviews") { WindowRouter.shared.open(.reviews) }
                    Button("Check for updates…") { store.checkForUpdates(manual: true) }
                        .disabled(store.snap.updateChecking)
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
        .frame(height: Metrics.footerRow)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    /// The bordered button, drawn in SwiftUI when rendering offscreen. Same size and outline.
    private func standIn(_ label: String, prominent: Bool = false, enabled: Bool = true) -> some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(prominent ? Color.white : p.ink.opacity(enabled ? 1 : 0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(prominent ? p.doingMark : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(p.ink.opacity(prominent ? 0 : 0.22), lineWidth: 1))
            )
    }

    @ViewBuilder
    private var footerButton: some View {
        // Set up applies only while config.toml has no repos. A configured user with no run gets Run now.
        let firstRun = store.snap.repoCount == 0 && !store.snap.running && !store.snap.dryRunning
        let dryRun = store.snap.dryRunning
        if offscreen {
            if store.snap.running { standIn("Stop") }
            else if dryRun { standIn("Open Glidepath", prominent: true) }
            else if store.snap.paused { standIn("Resume", prominent: true) }
            else if firstRun { standIn("Set up Glidepath…", prominent: true) }
            else { standIn("Run now") }
        } else if store.snap.running {
            Button("Stop") { confirmAndStop() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if dryRun {
            Button("Open Glidepath") { WindowRouter.shared.open(nil) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else if store.snap.paused {
            Button("Resume") { store.togglePause() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else if firstRun {
            Button("Set up Glidepath…") { WindowRouter.shared.openOnboarding() }
                .buttonStyle(.borderedProminent)
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

    /// Homebrew installs update after a confirmation; anything else opens the release page.
    private func confirmAndUpdate(_ update: UpdateCache) {
        guard store.updatesWithBrew else {
            if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update Glidepath to \(update.latest)?"
        alert.informativeText = "Homebrew rebuilds it from source, which takes about a minute. The app restarts when it's done."
            + (store.snap.running ? " A sweep is running, so the update starts when it ends." : "")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.startUpdate()
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

/// One PR row (docs/design.md, pass 4): the title on line 1 with the full width; line 2 has `#number · author`
/// on the left and the status (meter, then label, then mark) on the right; line 3 is the reason for changes.
/// A held draft adds Post and Discard at the right of line 2, outside the row's button.
struct PRRow: View {
    let row: RowModel
    let hovered: Bool
    let store: Store
    /// Paused: status labels and marks at 60% opacity.
    var dimmed = false
    var offscreen = false
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var p: Palette { Palette(scheme) }
    private var strip: Strip { row.strip }
    /// A draft waiting for Post or Discard. A post or discard that is running shows its word instead.
    private var showsDraftActions: Bool { strip.draft && strip.draftAction == nil }
    /// A PR skipped for size offers Review on line 2.
    private var showsReview: Bool { strip.skipReason == "size" && strip.verdict == .skipped }
    private var showsActions: Bool { showsDraftActions || showsReview }

    private var height: CGFloat {
        if strip.draftError != nil { return Metrics.rowThreeLines }
        if showsReview { return Metrics.rowThreeLines }
        if case .changes = row.status, strip.reason != nil { return Metrics.rowThreeLines }
        return Metrics.rowOneLine
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                if let url = URL(string: "https://github.com/\(strip.repo)/pull/\(strip.number)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                rowLabel
            }
            .buttonStyle(.plain)
            .focused($focused)
            if showsReview {
                reviewAction
            } else if showsDraftActions {
                draftActions
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(p.doingMark, lineWidth: 2)
                .padding(.horizontal, 8)
                .opacity(focused ? 1 : 0)
        )
        .onHover { inside in store.setHovered(inside ? strip.id : nil) }
    }

    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(strip.title ?? "Untitled PR")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.trailing, Metrics.chevronReserve)
            HStack(spacing: 0) {
                // verbatim: a plain string, so PR numbers are never grouped as 1,212.
                Text(verbatim: metaText)
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
                if strip.flagged {
                    Text("Flagged")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
                Spacer(minLength: 8)
                statusLine
            }
            .padding(.trailing, showsActions ? Metrics.draftActionsWidth : 0)
            if let error = strip.draftError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(p.error)
                    .lineLimit(1)
                    .help(error)
            } else if showsReview, let lines = strip.changedLines {
                Text(Presentation.sizeText(lines))
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
            } else if case .changes = row.status, let reason = strip.reason {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(p.changesText)
                    .lineLimit(1)
                    .help(reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.inset)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(p.ink.opacity(hovered ? 0.05 : 0))
                .padding(.horizontal, 8)
        )
        .overlay(alignment: .topTrailing) {
            // The chevron sits on line 1, in the strip the title leaves free.
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.secondary.opacity(hovered ? 0.5 : 0))
                .padding(.trailing, Metrics.inset)
                .padding(.top, 15)
        }
        .contentShape(Rectangle())
    }

    /// Post (accent, link style) and Discard (secondary) at the right of line 2. Sits above the row button, so the
    /// two never nest.
    private var draftActions: some View {
        HStack(spacing: 12) {
            if offscreen {
                Text("Post").font(.system(size: 12, weight: .medium)).foregroundStyle(p.doingText)
                Text("Discard").font(.system(size: 12)).foregroundStyle(p.secondary)
            } else {
                Button("Post") { confirmAndPost() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.doingText)
                    .disabled(store.snap.running)
                Button("Discard") { store.discardDraft(strip) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .disabled(store.snap.running)
            }
        }
        .padding(.trailing, Metrics.inset)
        .padding(.top, 23)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
    }

    /// Review for a PR over the size limit. Off while a sweep runs, since a second run would be refused.
    private var reviewAction: some View {
        HStack(spacing: 12) {
            if offscreen {
                Text("Review").font(.system(size: 12, weight: .medium)).foregroundStyle(p.doingText)
            } else {
                Button("Review") { confirmAndReview() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.doingText)
                    .disabled(store.snap.running)
            }
        }
        .padding(.trailing, Metrics.inset)
        .padding(.top, 23)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
    }

    private func confirmAndReview() {
        let alert = NSAlert()
        alert.messageText = "Review #\(strip.number) anyway?"
        alert.informativeText = store.reviewWarning(strip)
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.reviewPR(strip)
    }

    /// Posting is public and cannot be undone, so it asks first, with the verdict and the start of the body.
    private func confirmAndPost() {
        let preview = store.draftPreview(strip)
        let alert = NSAlert()
        alert.messageText = "Post the review on \(strip.repo) #\(strip.number)?"
        alert.informativeText = preview.verdict + "\n\n" + preview.body
        alert.addButton(withTitle: "Post")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.postDraft(strip)
    }

    private var metaText: String {
        var text = "#\(strip.number) · \(strip.author ?? "unknown")"
        if let carried = strip.carriedFrom {
            text += " · from \(HeaderCopy.clock(carried))"
        }
        return text
    }

    /// Meter (in flight only), then the label, then the mark, in one line.
    private var statusLine: some View {
        HStack(spacing: 6) {
            if let meter = row.meter, strip.draftAction == nil {
                meterView(meter)
            }
            let (shape, colour, label, text) = strip.draftAction.map { action in
                (StatusShape.hollow, p.doingMark, action == .posting ? "Posting…" : "Discarding…", p.doingText)
            } ?? statusParts
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(strip.carriedFrom == nil ? text : p.tertiary)
                .lineLimit(1)
            StatusMark(shape: shape, colour: strip.carriedFrom == nil ? colour : p.tertiary)
        }
        .opacity(dimmed ? 0.6 : 1)
    }

    private var statusParts: (StatusShape, Color, String, Color) {
        switch row.status {
        case .changes: return (.triangle, p.changesMark, "Changes", p.changesText)
        case .approved: return (.disc, p.approveMark, "Approved", p.approveText)
        case .skipped: return (.dash, p.skipMark, "Skipped", p.secondary)
        case .noResult: return (.hollow, p.skipMark, "No result", p.secondary)
        case .active(let phase): return (.hollow, p.doingMark, phase, p.doingText)
        case .queued: return (.hollow, p.skipMark, "Queued", p.secondary)
        }
    }

    /// Four dashes, 36 pt wide: done 35% ink, the current one the system blue, future 12% ink.
    private func meterView(_ segments: [MeterSegment]) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<segments.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(colour(segments[i]))
                    .frame(width: 6, height: 3)
            }
        }
        .frame(width: 36)
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
