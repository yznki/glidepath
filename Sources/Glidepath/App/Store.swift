import Foundation
import SwiftUI
import AppKit
import ServiceManagement

/// The end of a child's output, kept as it is read. The buffer is capped, so a chatty child cannot grow it without limit.
private final class OutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        text += String(decoding: data, as: UTF8.self)
        if text.count > 4096 { text = String(text.suffix(4096)) }
    }

    var lastLine: String {
        lock.lock()
        defer { lock.unlock() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
    }
}

extension NeedsItem {
    /// The call's id: the part of `id` after "<slug>#<n>/". Tend's commands take it.
    var callID: String { String(id.dropFirst("\(slug)#\(n)/".count)) }
}

/// Watches the state folders with DispatchSource, so the popover updates on each write without polling.
/// If a watched folder is deleted or renamed, the watcher recreates it and re-arms every source.
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let paths: [String]
    private let onChange: @Sendable () -> Void

    init(paths: [String], onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.onChange = onChange
        arm()
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources = []
        for path in paths {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let events = source.data
                if events.contains(.delete) || events.contains(.rename) {
                    self.arm()
                }
                self.onChange()
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        sources.forEach { $0.cancel() }
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    static let ackKey = "acknowledgedRunID"
    static let lastLookedKey = "lastLookedAt"

    @Published private(set) var snap: Snapshot
    /// Everything that needs the user, oldest first, and the one state every surface shows. Derived once per reload;
    /// the icon, popover, Dock badge and window all read these, so their counts agree.
    @Published private(set) var needsYou: [Need] = []
    @Published private(set) var status: GlideState = .quiet(next: nil)
    /// What Glidepath did since the popover was last closed. Nil when nothing, or before the first look.
    @Published private(set) var sinceLastLooked: SinceLastLooked?
    /// True when the store was built from a snapshot. Fixture stores never read or write disk, run checks or touch launchd.
    let isFixture: Bool
    /// Errors from actions in this app (run now, login item), shown until the next reload.
    @Published var actionError: String?
    /// Stamps that landed while the popover was open. The stamp settles once, then this clears.
    @Published private(set) var justLanded: Set<String> = []
    @Published var hovered: String?
    /// Draft posts and discards running from this app, and the last error of each.
    @Published private(set) var draftBusy: [String: DraftAction] = [:]
    @Published private(set) var draftErrors: [String: String] = [:]
    /// Tend commands run from the Needs rows, by item id: how many have failed, and the last one's error line. A failed
    /// count gives the row's hold button a new identity, so it starts again.
    @Published private(set) var tendFailures: [String: Int] = [:]
    @Published private(set) var tendErrors: [String: String] = [:]
    /// The Needs items whose tend command is running. Their buttons stay disabled until it finishes.
    @Published private(set) var tendBusy: Set<String> = []
    /// Tokens so far in the live sweep's session, read from its transcript every 2 s while the sweep runs. Zero otherwise.
    @Published private(set) var liveTokens: (total: Int, byPR: [Int: Int]) = (0, [:])
    private var liveTokenTask: Task<Void, Never>?
    private var liveTokenSession: String?

    let paths = Paths()
    let profileMotion: ProfileMotion
    var popoverOpen = false
    private var watcher: DirectoryWatcher?
    private var acknowledgedRunID: String?
    private var loggedUpdateFailure = false
    /// The dry run seen running most recently. When the lock is free, its notification goes out once.
    private var pendingDryRunID: String?
    private var dryRunCheckPending = false
    /// The sweep seen running most recently. When it finishes, its notification goes out once.
    private var pendingNoticeRunID: String?
    /// Set while a check waits for a running sweep to end, or retries a failed reinstall. Stopped once the job is current.
    private var jobReinstallTimer: Timer?
    private var jobReinstalling = false
    /// The last reinstall of the launchd job that failed. Cleared by the next check that succeeds.
    @Published private(set) var jobError: String? {
        didSet { if jobError != oldValue { derive() } }
    }
    /// The tend needs seen by the last load, by id. Nil until the first load, which notifies nothing.
    private var seenNeeds: Set<String>?
    /// The landed PRs seen by the last load, by id. Nil until the first load, which notifies nothing.
    private var seenLanded: Set<String>?
    /// Whether the first load has run, and the briefing time the last load saw. The first load notifies nothing.
    private var briefingLoaded = false
    private var seenBriefingAt: Date?

    /// `snapshot == nil` is the live app: registers at login and watches the state folders.
    /// A non-nil snapshot is fixed state for snapshot rendering.
    /// Fixtures pass a snapshot, and may pass the PRs that just landed and a shared motion (the hero GIF renders
    /// frames one after another with one motion, so landings animate across frames).
    init(snapshot: Snapshot? = nil, justLanded: Set<String> = [], motion: ProfileMotion = ProfileMotion()) {
        profileMotion = motion
        isFixture = snapshot != nil
        if let snapshot {
            snap = snapshot
            hovered = snapshot.hovered
            self.justLanded = justLanded
            derive()
            return
        }
        snap = Snapshot()
        acknowledgedRunID = UserDefaults.standard.string(forKey: Store.ackKey)
        try? FileManager.default.createDirectory(atPath: paths.runsDir, withIntermediateDirectories: true)
        registerLoginItemIfMoved()
        Notifier.setUp()
        let stateDir = paths.stateDir
        let runsDir = paths.runsDir
        watcher = DirectoryWatcher(paths: [stateDir, runsDir, paths.configDir, TendStore(paths: paths).dir]) {
            MainActor.assumeIsolated { Store.shared.reload() }
        }
        reload()
        checkIfDue(maxAge: Updates.maxAge)
        // Hourly: checkIfDue decides whether a fetch is due, so the cadence is maxAge and a sleeping Mac catches up.
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.checkIfDue(maxAge: Updates.maxAge) }
        }
    }

    var strips: [Strip] {
        Presentation.strips(from: snap.run).map { strip in
            var s = strip
            s.draftAction = draftBusy[strip.id]
            s.draftError = draftErrors[strip.id]
            return s
        }
    }

    /// The one Needs-you count.
    var needsCount: Int { needsYou.count }

    /// Reads the Needs-you list and the state from the snapshot. Publishes only what changed.
    private func derive() {
        let needs = NeedsYou.derive(snap)
        if needs != needsYou { needsYou = needs }
        let state = GlideState.derive(snap, needs: needs.count, jobError: jobError)
        if state != status { status = state }
    }

    /// The cached release, when it is newer than this build.
    var availableUpdate: UpdateCache? {
        guard let update = snap.update, Updates.isNewer(update.latest, than: Version.current) else { return nil }
        return update
    }

    /// A Homebrew install updates in place; anything else sends the user to the release page.
    var updatesWithBrew: Bool {
        guard let path = Bundle.main.executablePath else { return false }
        if case .homebrew = InstallKind.of(binary: path) { return true }
        return false
    }
    var headerKind: HeaderKind { Presentation.headerKind(snap, now: Date()) }

    /// Changes waiting: the last finished run had changes and the popover has not been opened since.
    var changesWaiting: Bool {
        guard let run = snap.run, run.finished != nil, run.id != acknowledgedRunID else { return false }
        return strips.contains { $0.verdict == .changes }
    }

    var glyph: GlyphState {
        if !snap.jobInstalled { return .failed }
        if snap.running { return .running(active: strips.filter(\.active).count) }
        if snap.dryRunning { return .running(active: 0) }
        if snap.paused { return .paused }
        if let run = snap.run, run.finished != nil, Presentation.failureMessage(run) != nil { return .failed }
        if changesWaiting {
            return .changesWaiting(count: strips.filter { $0.verdict == .changes }.count)
        }
        return .idle
    }

    func reload() {
        var s = Snapshot()
        let previous = Set(strips.filter { $0.verdict != nil }.map(\.id))
        do {
            s.run = try RunStore(paths: paths).loadCurrent()
        } catch {
            s.run = nil
            actionError = "could not read the last run: \(error)"
        }
        // A run is live only while its lock is held, so a crashed run never shows as running.
        s.running = (s.run.map { $0.finished == nil } ?? false) && RunLock.isHeld(paths.lockFile)
        s.dryRunning = !s.running && RunLock.isHeld(paths.lockFile)
        s.dryRun = s.dryRunning ? currentSweepRun(paths: paths, since: .distantPast) : nil
        s.paused = Pause.isPaused(paths)
        s.pausedSince = s.paused ? Pause.since(paths) : nil
        s.pausedUntil = s.paused ? Pause.until(paths) : nil
        s.jobInstalled = FileManager.default.fileExists(atPath: paths.plistFile)
        let config = try? Config.load(paths)
        s.nextRun = config.flatMap { ScheduleTimes.nextSweep(after: Date(), times: $0.schedule, days: $0.days) }
        s.postsReviews = config?.repos.contains { $0.posting == .review } ?? false
        s.schedule = config?.schedule ?? []
        s.repoCount = config?.repos.count ?? 0
        s.config = config
        // The shortcut follows the config as it is now, not only as it was at launch.
        if !isFixture { GlobalHotkey.shared.apply(config?.hotkey ?? .on) }
        s.hovered = snap.hovered
        s.update = Updates.cached(paths)
        s.checkUpdates = config?.checkUpdates ?? true
        s.maxChangedLines = config?.limits.maxChangedLines ?? 3000
        s.updateChecking = snap.updateChecking
        s.updatePhase = snap.updatePhase
        s.updateNote = snap.updateNote
        readTend(&s, config: config)

        // A sweep notifies once, when the file goes from running to finished. Dry runs never become current.
        if let run = s.run {
            if run.finished == nil {
                pendingNoticeRunID = run.id
            } else if run.id == pendingNoticeRunID {
                pendingNoticeRunID = nil
                // notify_changes_only: a sweep with no PR that needs changes stays quiet, but a failure still speaks.
                let hasChanges = run.repos.flatMap(\.prs).contains { $0.verdict == .changes }
                if config?.notify ?? true, let notice = Presentation.notice(run),
                   hasChanges || config?.notifyChangesOnly != true || Presentation.failureMessage(run) != nil {
                    Notifier.post(notice, runID: run.id, sound: config?.notifySound ?? .glass,
                                  respectFocus: config?.respectFocus ?? true)
                }
            }
        }

        // A dry run is not current, so its end is noticed here: the run file it left is read once the lock is free.
        if let dry = s.dryRun {
            pendingDryRunID = dry.id
            scheduleLockCheck()
        } else if let id = pendingDryRunID {
            pendingDryRunID = nil
            // A tend self-review is a dry run too, but it is the tend's own work and says nothing to the user.
            if let ended = try? RunStore(paths: paths).load(id), ended.finished != nil, ended.kind != "self-review",
               config?.notify ?? true {
                Notifier.post(Presentation.dryRunNotice(ended), runID: ended.id, sound: config?.notifySound ?? .glass,
                              respectFocus: config?.respectFocus ?? true)
            }
        }

        // Held drafts are shown from disk, whichever run wrote them. Notifications above used the run alone.
        s.run?.showDrafts(Drafts.all(paths))
        s.landedSeen = landedSeen(s, config: config)
        let landed = Set(Presentation.strips(from: s.run).filter { $0.verdict != nil }.map(\.id)).subtracting(previous)
        if popoverOpen && !landed.isEmpty {
            justLanded = landed
            let ids = landed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.justLanded.subtract(ids)
            }
        }
        snap = s
        derive()
        // Releasing tend's lock writes nothing the watcher sees, so while a tend check runs the store looks again.
        if s.tendRunning { scheduleLockCheck() }
        notifyNewNeeds(config: config)
        notifyLanded(config: config)
        notifyBriefing(config: config)
        reconcileJob()
        syncLiveTokens()
        hovered = hovered.flatMap { h in Presentation.strips(from: s.run).contains { $0.id == h } ? h : nil }
    }

    /// Reads tend's approach snapshot, tower and today's rounds. Rounds are read only while tending is on.
    private func readTend(_ s: inout Snapshot, config: Config?) {
        let tend = TendStore(paths: paths)
        s.tendOn = config?.tend.enabled ?? false
        s.tendRunning = RunLock.isHeld(paths.tendLockFile)
        s.queue = s.tendOn ? tend.loadQueue() : []
        s.usage = UsageState.load(paths).reading(reserve: config?.tend.usageReserve ?? TendConfig().usageReserve, now: Date())
        s.approach = tend.loadApproach()
        s.landed = tend.loadLanded()
        s.briefing = BriefingFile.load(paths)
        for plane in s.approach?.planes ?? [] {
            if let state = tend.load(plane.slug, plane.n) { s.prStates[plane.id] = state }
            if let plan = tend.loadSplit(plane.slug, plane.n) { s.splits[plane.id] = Split.effective(plan, now: Date()) }
        }
        // A landed PR that broke main needs a revert. Tend writes that need too; the id keeps one copy of each.
        if var approach = s.approach {
            for record in s.landed {
                if let need = Approach.revertNeed(record), !approach.needs.contains(where: { $0.id == need.id }) {
                    approach.needs.append(need)
                }
            }
            s.approach = approach
        }
        s.tower = tend.tower(limit: 30)
        for need in s.approach?.needs ?? [] where need.kind == "call" {
            if let call = tend.load(need.slug, need.n)?.calls.first(where: { $0.id == need.callID }) {
                s.calls[need.id] = call
            }
        }
        if s.tendOn {
            let today = Date()
            s.tendRounds = RunStore(paths: paths).loadAll(prefix: Runner.dayPrefix(today))
                .filter { $0.kind == "tend" && Calendar.current.isDate($0.started, inSameDayAs: today) }
                .sorted { $0.started > $1.started }
        }
    }

    /// Notifies once for each holding item (a held fix or a stuck PR) that was not in the last load. The first load
    /// notifies nothing, so opening the app does not repeat what is already waiting.
    private func notifyNewNeeds(config: Config?) {
        guard !isFixture, let needs = snap.approach?.needs else { return }
        defer { seenNeeds = Set(needs.map(\.id)) }
        guard let seen = seenNeeds, config?.notify ?? true else { return }
        for item in needs where !seen.contains(item.id) {
            let title: String
            switch item.kind {
            case "land": title = "#\(item.n) is ready to land"
            case "revert": title = "Main broke after #\(item.n)"
            default: title = "#\(item.n) needs you"
            }
            Notifier.post(SweepNotice(title: title, body: item.detail),
                          runID: "tend-\(item.id)-\(Store.hash(item.detail))",
                          sound: config?.notifySound ?? .glass, respectFocus: config?.respectFocus ?? true)
        }
    }

    /// Notifies once for each landed PR the last load did not have ("#n landed"). The first load notifies nothing.
    private func notifyLanded(config: Config?) {
        guard !isFixture else { return }
        let ids = snap.landed.map { "\($0.slug)#\($0.n)" }
        defer { seenLanded = Set(ids) }
        guard let seen = seenLanded, config?.notify ?? true else { return }
        for record in snap.landed where !seen.contains("\(record.slug)#\(record.n)") {
            Notifier.post(SweepNotice(title: "#\(record.n) landed", body: record.title),
                          runID: "tend-landed-\(record.slug)#\(record.n)",
                          sound: config?.notifySound ?? .glass, respectFocus: config?.respectFocus ?? true)
        }
    }

    /// Notifies once when a new briefing appears (its time moves). The first load notifies nothing.
    private func notifyBriefing(config: Config?) {
        guard !isFixture else { return }
        let first = !briefingLoaded
        let previous = seenBriefingAt
        briefingLoaded = true
        seenBriefingAt = snap.briefing?.at
        guard !first, let briefing = snap.briefing, briefing.at != previous, config?.notify ?? true else { return }
        Notifier.post(SweepNotice(title: "Glidepath briefing",
                                  body: "\(briefing.landed.count) landed, \(briefing.blocked.count) blocked"),
                      runID: "tend-briefing-\(Int(briefing.at.timeIntervalSince1970))",
                      sound: config?.notifySound ?? .glass, respectFocus: config?.respectFocus ?? true)
    }

    /// Dismisses the briefing card: stamps `dismissedAt` in the briefing file, then reads the state again.
    func dismissBriefing() {
        guard !isFixture else { return }
        do {
            try BriefingFile.dismiss(paths)
        } catch {
            actionError = "could not dismiss the briefing: \(error.localizedDescription)"
        }
        reload()
    }

    /// The first-seen times after a load: the ones already known, plus each new landed PR at now. On the first load every
    /// PR is recorded as seen long ago, so nothing glides in at launch.
    private func landedSeen(_ s: Snapshot, config: Config?) -> [String: Date] {
        guard !isFixture else { return s.landedSeen }
        var seen = snap.landedSeen
        for record in s.landed {
            let id = "\(record.slug)#\(record.n)"
            if seen[id] == nil { seen[id] = seenLanded == nil ? .distantPast : Date() }
        }
        return seen
    }

    /// A stable hash of a string, for notification ids: `hashValue` changes between launches.
    private static func hash(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(5381)) { $0 &* 33 &+ UInt32($1) }
    }

    /// Starts the token poller once per session while a sweep runs, and stops it when the sweep ends. The transcript is
    /// read off the main actor; the totals are published on it.
    private func syncLiveTokens() {
        guard !isFixture, snap.running, let run = snap.run, let session = run.sessionId, let cwd = run.sessionCwd else {
            liveTokenTask?.cancel()
            liveTokenTask = nil
            liveTokenSession = nil
            if liveTokens.total != 0 || !liveTokens.byPR.isEmpty { liveTokens = (0, [:]) }
            return
        }
        guard liveTokenSession != session else { return }
        liveTokenTask?.cancel()
        liveTokenSession = session
        let paths = self.paths
        let kept = Set(run.repos.flatMap { $0.prs.map(\.n) })
        liveTokenTask = Task { [weak self] in
            while !Task.isCancelled {
                let usage = await Task.detached(priority: .utility) {
                    Transcript.usage(paths: paths, cwd: cwd, sessionId: session, keptPRs: kept)
                }.value
                guard !Task.isCancelled else { return }
                if let self, usage.total != self.liveTokens.total || usage.byPR != self.liveTokens.byPR {
                    self.liveTokens = (usage.total, usage.byPR)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// The lock is released after the run file is written, and releasing it writes nothing the watcher sees. So while a
    /// dry run or a tend check holds its lock, the store checks again shortly, and notices its end.
    private func scheduleLockCheck() {
        guard !dryRunCheckPending, !isFixture else { return }
        dryRunCheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.dryRunCheckPending = false
            self.reload()
        }
    }

    /// Brings the launchd job in line with config.toml. Runs on every reload, so a schedule save made while a sweep held
    /// the run lock is reinstalled once the sweep's state is written. While the lock is held, or a reinstall failed, it
    /// checks again every few seconds.
    func reconcileJob() {
        guard !isFixture, !jobReinstalling else { return }
        guard ScheduleEditor.jobNeedsReinstall(paths) else {
            stopJobTimer()
            jobError = nil
            return
        }
        guard !RunLock.isHeld(paths.lockFile) else {
            startJobTimer()
            return
        }
        jobReinstalling = true
        let paths = self.paths
        Task {
            do {
                try await Task.detached { try ScheduleEditor.installJob(try Config.load(paths), paths: paths) }.value
                jobError = nil
                stopJobTimer()
            } catch {
                jobError = "could not reinstall the schedule: \(error.localizedDescription)"
                startJobTimer()
            }
            jobReinstalling = false
        }
    }

    private func startJobTimer() {
        guard jobReinstallTimer == nil else { return }
        jobReinstallTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileJob() }
        }
    }

    private func stopJobTimer() {
        jobReinstallTimer?.invalidate()
        jobReinstallTimer = nil
    }

    /// Called when the popover appears. Opening it after a run ends clears "changes waiting".
    func popoverOpened() {
        popoverOpen = true
        if let run = snap.run, run.finished != nil {
            acknowledgedRunID = run.id
            UserDefaults.standard.set(run.id, forKey: Store.ackKey)
        }
        reload()
        loadSinceLastLooked()
        checkIfDue(maxAge: Updates.popoverMaxAge)
    }

    /// Closing the popover is a look: the next "Since you last looked" starts here.
    func popoverClosed() {
        popoverOpen = false
        guard !isFixture else { return }
        UserDefaults.standard.set(Date(), forKey: Store.lastLookedKey)
    }

    /// Reads the runs since the last look, a week at most, by their day-prefixed ids. Nothing before the first look.
    private func loadSinceLastLooked() {
        guard !isFixture, let last = UserDefaults.standard.object(forKey: Store.lastLookedKey) as? Date else { return }
        let now = Date()
        let from = max(last, now.addingTimeInterval(-7 * 86_400))
        var runs: [RunState] = []
        var day = Calendar.current.startOfDay(for: from)
        while day <= now {
            runs += RunStore(paths: paths).loadAll(prefix: Runner.dayPrefix(day))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let since = SinceLastLooked.make(runs: runs, landed: snap.landed, after: last)
        sinceLastLooked = since.isEmpty ? nil : since
    }

    /// Stops the running sweep: signals its process group, then records the run as finished. Reviews already
    /// posted stay posted; the PRs not yet reviewed show "No result". A stopped run is not a failed run.
    func stopRun() {
        guard Stop.sweep(paths, run: sweepRunID) else {
            actionError = "no sweep to stop"
            return
        }
        actionError = nil
        reload()
    }

    /// Stops everything running: a sweep or dry run, and a tend check with its round. Nothing more goes to GitHub from
    /// either; what was already posted stays. The next scheduled check starts as usual unless the user also pauses.
    func stopAll() {
        guard !isFixture else { return }
        actionError = Stop.all(paths, run: sweepRunID) ? nil : "nothing to stop"
        reload()
    }

    /// The run file a stop records as finished. A dry run is not the current run, so it is the dry run's own file.
    private var sweepRunID: String? { snap.dryRunning ? snap.dryRun?.id : snap.run?.id }

    // MARK: Actions

    /// Posts a held draft through `glidepath drafts post`, the same command a terminal would run.
    func postDraft(_ strip: Strip) {
        guard !snap.running else {
            draftErrors[strip.id] = "a sweep is running; try again when it ends"
            return
        }
        runCommand(["drafts", "post", strip.repo, String(strip.number)], id: strip.id, action: .posting)
    }

    func discardDraft(_ strip: Strip) {
        guard !snap.running else {
            draftErrors[strip.id] = "a sweep is running; try again when it ends"
            return
        }
        runCommand(["drafts", "discard", strip.repo, String(strip.number)], id: strip.id, action: .discarding)
    }

    /// Reviews a PR skipped for size, through `glidepath review`. The run shows its progress on the slope, so the row
    /// shows nothing while it starts; a refusal (another run holds the lock) lands on the row.
    func reviewPR(_ strip: Strip) {
        guard !snap.running else {
            draftErrors[strip.id] = "a sweep is running; try again when it ends"
            return
        }
        runCommand(["review", strip.repo, String(strip.number)], id: strip.id, action: nil)
    }

    /// The Review confirm text for a PR over the limit: its size, the limit, and a rough token estimate when the last
    /// finished run allows one.
    func reviewWarning(_ strip: Strip) -> String {
        let last = snap.run.flatMap { $0.finished == nil ? nil : $0 }
        return Presentation.reviewWarning(changedLines: strip.changedLines ?? 0, limit: snap.maxChangedLines, last: last)
    }

    /// The verdict line and the start of the body, for the confirm alert before a post.
    func draftPreview(_ strip: Strip) -> (verdict: String, body: String) {
        let verdict = strip.verdict == .changes ? "Verdict: changes" : "Verdict: approve"
        let body = Drafts.newest(paths, slug: strip.repo, n: strip.number)?.draft.body ?? ""
        return (verdict, body.count > 300 ? String(body.prefix(300)) + "…" : body)
    }

    /// Runs a draft command as a process. Its output is read as it is written, so a child never waits on a full pipe;
    /// its last line becomes the row's error if it fails.
    private func runCommand(_ args: [String], id: String, action: DraftAction?) {
        guard let binary = Bundle.main.executablePath else {
            draftErrors[id] = "cannot find the glidepath binary"
            return
        }
        draftErrors[id] = nil
        if let action { draftBusy[id] = action }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.environment = Runner.environment(paths)
        let output = Pipe()
        let tail = OutputTail()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { tail.append(data) }
        }
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { p in
            output.fileHandleForReading.readabilityHandler = nil
            tail.append(output.fileHandleForReading.readDataToEndOfFile())
            let last = tail.lastLine
            let ok = p.terminationStatus == 0
            DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.finishDraftCommand(id, ok: ok, message: last) } }
        }
        do {
            try process.run()
        } catch {
            draftBusy[id] = nil
            draftErrors[id] = "run failed: \(error.localizedDescription)"
        }
    }

    private func finishDraftCommand(_ id: String, ok: Bool, message: String) {
        draftBusy[id] = nil
        draftErrors[id] = ok ? nil : (message.isEmpty ? "failed; see the log" : message)
        reload()
    }

    func togglePause() {
        if snap.paused { resume() } else { pause(until: nil) }
    }

    /// Pause stops everything: what is running now, and every check (reviews and the user's PRs) until `until`, or
    /// until Resume when nil.
    func pause(until: Date?) {
        do {
            try Pause.set(true, paths, until: until)
            actionError = nil
        } catch {
            actionError = "pause: \(error.localizedDescription)"
            reload()
            return
        }
        if !isFixture { _ = Stop.all(paths, run: sweepRunID) }
        reload()
    }

    func resume() {
        do {
            try Pause.set(false, paths)
            actionError = nil
        } catch {
            actionError = "pause: \(error.localizedDescription)"
        }
        reload()
    }

    /// Starts `glidepath run` with the PATH the job uses, output appended to the log. With a slug, only that repo.
    func runNow(repo: String? = nil) {
        spawn(repo.map { ["run", "--repo", $0] } ?? ["run"], label: "run now")
    }

    /// Starts `glidepath review` for one PR or one author's PRs, as a terminal would. Refused while a sweep or a dry run
    /// runs, since they take the same lock. A refusal from the lock lands in the log. False when it did not start.
    @discardableResult
    func review(_ target: ReviewTarget) -> Bool {
        guard !snap.running && !snap.dryRunning else {
            actionError = "a sweep is running; try again when it ends"
            return false
        }
        return spawn(target.arguments, label: "review")
    }

    /// Starts the glidepath binary with `args`, the PATH the job uses, and output appended to the log. A failure to start
    /// is shown as `label: reason`. False when it did not start.
    @discardableResult
    private func spawn(_ args: [String], label: String) -> Bool {
        guard let binary = Bundle.main.executablePath else {
            actionError = "cannot find the glidepath binary"
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.environment = Runner.environment(paths)
        attachLog(process)
        do {
            try process.run()
            actionError = nil
            return true
        } catch {
            actionError = "\(label): \(error.localizedDescription)"
            return false
        }
    }

    /// Points a child's stdout and stderr at the log, appending. createFile would truncate it.
    private func attachLog(_ process: Process) {
        try? FileManager.default.createDirectory(atPath: (paths.logFile as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: paths.logFile) {
            FileManager.default.createFile(atPath: paths.logFile, contents: nil)
        }
        if let log = FileHandle(forWritingAtPath: paths.logFile) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        }
    }

    /// Runs `glidepath tend <args>` (push, discard, retry) with the job's environment, off the main thread. A failure
    /// shows its last output line; either way the state is read again after.
    /// Runs `glidepath tend <args>`. `item` is the Needs row it came from, whose failure count and error it updates.
    /// `onDone` gets whether the command succeeded, once the state is read again. A sheet uses it to stay open on failure.
    /// `timeout` is how long the command may run; a split plan or build runs for hours.
    func tendCommand(_ args: [String], item: String? = nil, timeout: TimeInterval = 600, onDone: ((Bool) -> Void)? = nil) {
        guard let binary = Bundle.main.executablePath else {
            actionError = "cannot find the glidepath binary"
            onDone?(false)
            return
        }
        // One command at a time per item: a second click while one runs does nothing.
        if let item {
            guard !tendBusy.contains(item) else {
                onDone?(false)
                return
            }
            tendBusy.insert(item)
        }
        let env = Runner.environment(paths)
        Task {
            let result = await Task.detached { Shell.run(binary, ["tend"] + args, env: env, timeout: timeout) }.value
            if let item { tendBusy.remove(item) }
            if result.ok {
                actionError = nil
                if let item { tendErrors[item] = nil }
            } else {
                let text = result.stderr.isEmpty ? result.stdout : result.stderr
                let last = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init)
                actionError = "tend \(args.first ?? ""): \(last ?? "failed")"
                if let item {
                    tendFailures[item, default: 0] += 1
                    let first = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first
                    tendErrors[item] = first.map(String.init) ?? last ?? "failed"
                }
            }
            reload()
            onDone?(result.ok)
        }
    }

    /// The approach plane for a PR, when tend has one.
    func approachPlane(_ slug: String, _ n: Int) -> ApproachPlane? {
        snap.approach?.planes.first { $0.slug == slug && $0.n == n }
    }

    /// The repo's playbook: the fixture's in snapshot mode, the file otherwise.
    func playbook(_ slug: String) -> Playbook {
        if isFixture { return snap.playbooks[slug] ?? Playbook() }
        return Playbook.load(slug, paths: paths)
    }

    // MARK: Updates

    /// Checks GitHub off the main thread. A manual check reports what it found for 4 s; an automatic one is silent
    /// except for its first failure, which goes to the log.
    func checkForUpdates(manual: Bool) {
        guard !snap.updateChecking, snap.updatePhase != .updating else { return }
        snap.updateChecking = true
        let paths = self.paths
        Task {
            let result = await Task.detached { Result { try Updates.fetchLatest() } }.value
            snap.updateChecking = false
            switch result {
            case .success(let release):
                try? Updates.store(UpdateCache(checked: Date(), latest: release.version, url: release.url), paths)
                reload()
                if manual {
                    flashNote(availableUpdate == nil ? "You're on the latest version" : "Glidepath \(release.version) is available")
                }
            case .failure(let error):
                if !loggedUpdateFailure {
                    loggedUpdateFailure = true
                    Updates.log("\(error)", paths)
                }
                if manual { flashNote("Couldn't check for updates") }
            }
        }
    }

    /// Automatic checks run when the cache is missing or older than `maxAge`, and only while checks are on.
    func checkIfDue(maxAge: TimeInterval) {
        guard snap.checkUpdates, Updates.isDue(snap.update, now: Date(), maxAge: maxAge) else { return }
        checkForUpdates(manual: false)
    }

    private func flashNote(_ text: String) {
        snap.updateNote = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.snap.updateNote == text else { return }
            self.snap.updateNote = nil
        }
    }

    /// Runs `glidepath update --wait`. It waits for a sweep to end, upgrades through brew and exits; the app then
    /// relaunches from its link, which the upgrade has pointed at the new version.
    func startUpdate() {
        guard let binary = Bundle.main.executablePath else {
            snap.updatePhase = .failed
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["update", "--wait"]
        // The same PATH the job uses, so brew, gh and claude resolve as they do for scheduled runs.
        process.environment = Runner.environment(paths)
        attachLog(process)
        process.terminationHandler = { p in
            let ok = p.terminationStatus == 0
            DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.finishUpdate(ok: ok) } }
        }
        do {
            try process.run()
            snap.updatePhase = .updating
        } catch {
            snap.updatePhase = .failed
        }
    }

    private func finishUpdate(ok: Bool) {
        guard ok else {
            snap.updatePhase = .failed
            return
        }
        // The sleep gives the upgrade's new link time to settle before `open` reads it.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", paths.appLink]
        do {
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            snap.updatePhase = .failed
        }
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: paths.logFile))
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            actionError = nil
        } catch {
            actionError = "login item: \(error.localizedDescription)"
        }
    }

    var loginItemOn: Bool { isFixture ? snap.loginOn : SMAppService.mainApp.status == .enabled }

    /// Every run the window reads: the fixture's runs in snapshot mode, the run files otherwise.
    func allRuns() -> [RunState] {
        if isFixture { return snap.runs ?? [] }
        return RunStore(paths: paths).loadAll()
    }

    /// The review text for one PR in one run: the fixture's in snapshot mode, the text store otherwise.
    func reviewText(runId: String, slug: String, n: Int) -> ReviewTextRecord? {
        if isFixture { return snap.reviewTexts["\(runId)|\(slug)#\(n)"] }
        return ReviewText.read(paths, runId: runId, slug: slug, n: n)
    }

    /// Login items are keyed by bundle path. Re-register when the app runs from a new path,
    /// so the item never points at a build folder.
    private func registerLoginItemIfMoved() {
        let bundlePath = Bundle.main.bundlePath
        if UserDefaults.standard.string(forKey: "loginItemPath") != bundlePath {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(bundlePath, forKey: "loginItemPath")
        }
    }
}
