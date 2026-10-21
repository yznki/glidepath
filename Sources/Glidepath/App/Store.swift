import Foundation
import SwiftUI
import AppKit
import ServiceManagement

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

    var id: String { "\(repo)#\(number)" }
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
    var hovered: String?
}

/// Blip positions and ping timers. The radar reads and writes this every frame; it is not SwiftUI state,
/// so animating it does not re-render the view tree.
final class RadarMotion {
    var radius: [String: Double] = [:]
    var lastTarget: [String: Double] = [:]
    var pingStart: [String: Date] = [:]
    var lastFrame: Date?

    /// Eases each blip toward its target radius and starts a ping when a PR lands at the centre.
    func advance(targets: [String: Double], now: Date, reduceMotion: Bool) {
        let dt = lastFrame.map { now.timeIntervalSince($0) } ?? 0
        lastFrame = now
        for (id, target) in targets {
            let current = radius[id] ?? target
            if reduceMotion || radius[id] == nil {
                radius[id] = target
            } else {
                // Rate 5 per second approximates the design's spring (response 0.45 s, damping 0.86).
                radius[id] = current + (target - current) * (1 - exp(-5 * dt))
            }
            if let previous = lastTarget[id], previous > 0.18, target <= 0.18, !reduceMotion {
                pingStart[id] = now
            }
            lastTarget[id] = target
        }
    }
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

    let paths = Paths()
    let motion = RadarMotion()
    var popoverOpen = false
    private var watcher: DirectoryWatcher?
    private var acknowledgedRunID: String?

    /// `snapshot == nil` is the live app: registers at login and watches the state folders.
    /// A non-nil snapshot is fixed state for snapshot rendering.
    init(snapshot: Snapshot? = nil) {
        if let snapshot {
            snap = snapshot
            hovered = snapshot.hovered
            return
        }
        snap = Snapshot()
        acknowledgedRunID = UserDefaults.standard.string(forKey: Store.ackKey)
        try? FileManager.default.createDirectory(atPath: paths.runsDir, withIntermediateDirectories: true)
        registerLoginItemIfMoved()
        let stateDir = paths.stateDir
        let runsDir = paths.runsDir
        watcher = DirectoryWatcher(paths: [stateDir, runsDir]) {
            MainActor.assumeIsolated { Store.shared.reload() }
        }
        reload()
    }

    var strips: [Strip] { Store.strips(from: snap.run) }
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
        if changesWaiting { return .changesWaiting }
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
        s.hovered = snap.hovered

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
    }

    func popoverClosed() {
        popoverOpen = false
    }

    func setHovered(_ id: String?) {
        hovered = id
    }

    // MARK: Actions

    func togglePause() {
        do {
            try Pause.set(!snap.paused, paths)
            actionError = nil
        } catch {
            actionError = "pause: \(error.localizedDescription)"
        }
        reload()
    }

    /// Starts `glidepath run` with the PATH the job uses, output appended to the log.
    func runNow() {
        guard let binary = Bundle.main.executablePath else {
            actionError = "cannot find the glidepath binary"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["run"]
        process.environment = Runner.environment(paths)
        // Append to the log. createFile would truncate it.
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
        do {
            try process.run()
            actionError = nil
        } catch {
            actionError = "run now: \(error.localizedDescription)"
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
                      stage: pr.stage.rank + 1, active: pr.active, verdict: pr.verdict, tokens: pr.tokens)
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
