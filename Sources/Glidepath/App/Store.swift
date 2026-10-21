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

/// One PR as the popover and the radar draw it.
struct Strip: Identifiable, Equatable {
    let repo: String
    let number: Int
    var author: String?
    var title: String?
    var reason: String?
    var stage: Int          // 1...4: gather, review, check, post
    var active: Bool
    var verdict: Verdict?
    var tokens: Int
    var carriedFrom: Date? = nil
    var draft = false
    var flagged = false
    /// A draft post or discard is running for this row: the status reads "Posting…" or "Discarding…".
    var draftAction: DraftAction? = nil
    var posting: Bool { draftAction == .posting }
    /// The last draft post or discard failed: its last output line, shown on line 3.
    var draftError: String? = nil
    /// "size" on a PR skipped for size: its row offers Review.
    var skipReason: String? = nil
    var changedLines: Int? = nil

    var id: String { "\(repo)#\(number)" }
}

/// A draft command the app is running for one row.
enum DraftAction: Equatable {
    case posting, discarding
}

/// The menu bar app's own update work. `updating` runs `glidepath update --wait`; `failed` stays until the next try.
enum UpdatePhase: Equatable {
    case idle, updating, failed
}

/// Everything the popover shows. `Store` fills it from disk; snapshot rendering fills it with fixtures.
struct Snapshot {
    var run: RunState?
    var running = false
    var paused = false
    var pausedSince: Date?
    var jobInstalled = true
    var nextRun: Date?
    var postsReviews = false
    var schedule: [ScheduleTime] = []
    var repoCount = 0
    /// The parsed config, for the Repos section. Nil when there is no config or it does not parse.
    var config: Config?
    /// `max_changed_lines`, for the Review warning.
    var maxChangedLines = 3000
    var hovered: String?
    /// The cached latest release. The popover offers it when it is newer than this build.
    var update: UpdateCache?
    var checkUpdates = true
    var updateChecking = false
    var updatePhase: UpdatePhase = .idle
    /// The result of "Check for updates…", shown for 4 s.
    var updateNote: String?
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

    @Published private(set) var snap: Snapshot
    /// Errors from actions in this app (run now, login item), shown until the next reload.
    @Published var actionError: String?
    /// Stamps that landed while the popover was open. The stamp settles once, then this clears.
    @Published private(set) var justLanded: Set<String> = []
    @Published var hovered: String?
    /// Draft posts and discards running from this app, and the last error of each.
    @Published private(set) var draftBusy: [String: DraftAction] = [:]
    @Published private(set) var draftErrors: [String: String] = [:]

    let paths = Paths()
    let profileMotion: ProfileMotion
    var popoverOpen = false
    private var watcher: DirectoryWatcher?
    private var acknowledgedRunID: String?
    private var loggedUpdateFailure = false
    /// The sweep seen running most recently. When it finishes, its notification goes out once.
    private var pendingNoticeRunID: String?

    /// `snapshot == nil` is the live app: registers at login and watches the state folders.
    /// A non-nil snapshot is fixed state for snapshot rendering.
    /// Fixtures pass a snapshot, and may pass the PRs that just landed and a shared motion (the hero GIF renders
    /// frames one after another with one motion, so landings animate across frames).
    init(snapshot: Snapshot? = nil, justLanded: Set<String> = [], motion: ProfileMotion = ProfileMotion()) {
        profileMotion = motion
        if let snapshot {
            snap = snapshot
            hovered = snapshot.hovered
            self.justLanded = justLanded
            return
        }
        snap = Snapshot()
        acknowledgedRunID = UserDefaults.standard.string(forKey: Store.ackKey)
        try? FileManager.default.createDirectory(atPath: paths.runsDir, withIntermediateDirectories: true)
        registerLoginItemIfMoved()
        Notifier.setUp()
        let stateDir = paths.stateDir
        let runsDir = paths.runsDir
        watcher = DirectoryWatcher(paths: [stateDir, runsDir]) {
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
        Store.strips(from: snap.run).map { strip in
            var s = strip
            s.draftAction = draftBusy[strip.id]
            s.draftError = draftErrors[strip.id]
            return s
        }
    }

    /// Reviews held as drafts, from every run.
    var draftCount: Int { strips.filter(\.draft).count }

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
    var errorText: String? { actionError ?? snap.run.flatMap { Presentation.failureMessage($0) } }
    var headerKind: HeaderKind { Presentation.headerKind(snap, now: Date()) }

    /// Changes waiting: the last finished run had changes and the popover has not been opened since.
    var changesWaiting: Bool {
        guard let run = snap.run, run.finished != nil, run.id != acknowledgedRunID else { return false }
        return strips.contains { $0.verdict == .changes }
    }

    var glyph: GlyphState {
        if !snap.jobInstalled { return .failed }
        if snap.running { return .running(active: strips.filter(\.active).count) }
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
        s.paused = Pause.isPaused(paths)
        s.pausedSince = s.paused ? Pause.since(paths) : nil
        s.jobInstalled = FileManager.default.fileExists(atPath: paths.plistFile)
        let config = try? Config.load(paths)
        s.nextRun = config.flatMap { Store.nextSweep(schedule: $0.schedule, after: Date()) }
        s.postsReviews = config?.repos.contains { $0.posting == .review } ?? false
        s.schedule = config?.schedule ?? []
        s.repoCount = config?.repos.count ?? 0
        s.config = config
        s.hovered = snap.hovered
        s.update = Updates.cached(paths)
        s.checkUpdates = config?.checkUpdates ?? true
        s.maxChangedLines = config?.limits.maxChangedLines ?? 3000
        s.updateChecking = snap.updateChecking
        s.updatePhase = snap.updatePhase
        s.updateNote = snap.updateNote

        // A sweep notifies once, when the file goes from running to finished. Dry runs never become current.
        if let run = s.run {
            if run.finished == nil {
                pendingNoticeRunID = run.id
            } else if run.id == pendingNoticeRunID {
                pendingNoticeRunID = nil
                if config?.notify ?? true, let notice = Presentation.notice(run) {
                    Notifier.post(notice, runID: run.id)
                }
            }
        }

        // Held drafts are shown from disk, whichever run wrote them. Notifications above used the run alone.
        s.run?.showDrafts(Drafts.all(paths))
        let landed = Set(Store.strips(from: s.run).filter { $0.verdict != nil }.map(\.id)).subtracting(previous)
        if popoverOpen && !landed.isEmpty {
            justLanded = landed
            let ids = landed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.justLanded.subtract(ids)
            }
        }
        snap = s
        hovered = hovered.flatMap { h in Store.strips(from: s.run).contains { $0.id == h } ? h : nil }
    }

    /// Called when the popover appears. Opening it after a run ends clears "changes waiting".
    func popoverOpened() {
        popoverOpen = true
        if let run = snap.run, run.finished != nil {
            acknowledgedRunID = run.id
            UserDefaults.standard.set(run.id, forKey: Store.ackKey)
        }
        reload()
        checkIfDue(maxAge: Updates.popoverMaxAge)
    }

    func popoverClosed() {
        popoverOpen = false
    }

    func setHovered(_ id: String?) {
        hovered = id
    }

    /// Stops the running sweep: signals its process group, then records the run as finished. Reviews already
    /// posted stay posted; the PRs not yet reviewed show "No result". A stopped run is not a failed run.
    func stopRun() {
        guard let text = try? String(contentsOfFile: paths.pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else {
            actionError = "no sweep to stop"
            return
        }
        _ = kill(-pid, SIGTERM)
        try? RunStore(paths: paths).mutate(snap.run?.id ?? "") { run in
            if run.finished == nil { run.finish(at: Date(), error: nil) }
        }
        actionError = nil
        reload()
    }

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

    /// Writes the HTML dashboard and opens it. The CLI does the work, so the page is the same either way.
    func openDashboard() {
        guard let binary = Bundle.main.executablePath else {
            actionError = "cannot find the glidepath binary"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["dashboard"]
        process.environment = Runner.environment(paths)
        attachLog(process)
        do {
            try process.run()
            actionError = nil
        } catch {
            actionError = "dashboard: \(error.localizedDescription)"
        }
    }

    func togglePause() {
        do {
            try Pause.set(!snap.paused, paths)
            actionError = nil
        } catch {
            actionError = "pause: \(error.localizedDescription)"
        }
        reload()
    }

    /// Starts `glidepath run` with the PATH the job uses, output appended to the log. With a slug, only that repo.
    func runNow(repo: String? = nil) {
        guard let binary = Bundle.main.executablePath else {
            actionError = "cannot find the glidepath binary"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = repo.map { ["run", "--repo", $0] } ?? ["run"]
        process.environment = Runner.environment(paths)
        attachLog(process)
        do {
            try process.run()
            actionError = nil
        } catch {
            actionError = "run now: \(error.localizedDescription)"
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

    var loginItemOn: Bool { SMAppService.mainApp.status == .enabled }

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

    // MARK: Derivation

    nonisolated static func strips(from run: RunState?) -> [Strip] {
        guard let run else { return [] }
        return run.repos.flatMap { repo in
            repo.prs.map { pr in
                Strip(repo: repo.slug, number: pr.n, author: pr.author, title: pr.title, reason: pr.reason,
                      stage: pr.stage.rank + 1, active: pr.active, verdict: pr.verdict, tokens: pr.tokens,
                      carriedFrom: pr.carriedFrom, draft: pr.draft ?? false, flagged: pr.flagged ?? false,
                      skipReason: pr.skipReason, changedLines: pr.changedLines)
            }
        }
    }

    /// The first scheduled time after `date`, today or tomorrow.
    nonisolated static func nextSweep(schedule: [ScheduleTime], after date: Date) -> Date? {
        let cal = Calendar.current
        let times = schedule.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        for dayOffset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            for t in times {
                if let candidate = cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day),
                   candidate > date {
                    return candidate
                }
            }
        }
        return nil
    }
}
