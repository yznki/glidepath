import Foundation
import SwiftUI
import AppKit
import ServiceManagement

/// One PR as the popover draws it.
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
    var posted: Bool { verdict == .approve || verdict == .changes }
}

/// Everything the popover shows. `Store` fills it from disk; `--snapshot` fills it with fixtures.
struct Snapshot {
    var run: RunState?
    var running = false
    var paused = false
    var jobInstalled = true
    var nextRun: Date?
    var postsReviews = false
    var lastError: String?
}

/// Watches the state folders with DispatchSource, so the popover updates on each write without polling.
/// If a watched folder is deleted or renamed, the watcher recreates it and re-arms every source, so
/// the next write is still seen.
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

    @Published private(set) var snap: Snapshot
    /// Errors from actions in this app (run now, login item), shown until the next reload.
    @Published var actionError: String?

    let paths = Paths()
    private var watcher: DirectoryWatcher?

    /// `snapshot == nil` is the live app: registers at login and watches the state folders.
    /// A non-nil snapshot is fixed state for `--snapshot` rendering.
    init(snapshot: Snapshot? = nil) {
        if let snapshot {
            snap = snapshot
            return
        }
        snap = Snapshot()
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
    var done: Int { strips.filter { $0.verdict != nil }.count }
    var errorText: String? { actionError ?? snap.lastError }

    func reload() {
        var s = Snapshot()
        do {
            s.run = try RunStore(paths: paths).loadCurrent()
        } catch {
            s.lastError = "could not read the last run: \(error)"
        }
        // A run is live only while its lock is held, so a crashed run never shows as running.
        s.lastError = s.lastError ?? s.run?.error
        s.running = (s.run.map { $0.finished == nil } ?? false) && RunLock.isHeld(paths.lockFile)
        s.paused = Pause.isPaused(paths)
        s.jobInstalled = FileManager.default.fileExists(atPath: paths.plistFile)
        let config = try? Config.load(paths)
        s.nextRun = config.flatMap { Store.nextSweep(schedule: $0.schedule, after: Date()) }
        s.postsReviews = config?.repos.contains { $0.posting == .review } ?? false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            snap = s
        }
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

    /// Starts `review-radar run` with the PATH the job uses, output appended to the log.
    func runNow() {
        guard let binary = Bundle.main.executablePath else {
            actionError = "cannot find the review-radar binary"
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

    static func strips(from run: RunState?) -> [Strip] {
        guard let run else { return [] }
        return run.repos.flatMap { repo in
            repo.prs.map { pr in
                Strip(repo: repo.slug, number: pr.n, author: pr.author, title: pr.title, reason: pr.reason,
                      stage: pr.stage.rank + 1, active: pr.active, verdict: pr.verdict, tokens: pr.tokens)
            }
        }
    }

    /// The first scheduled time after `date`, today or tomorrow.
    static func nextSweep(schedule: [ScheduleTime], after date: Date) -> Date? {
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
