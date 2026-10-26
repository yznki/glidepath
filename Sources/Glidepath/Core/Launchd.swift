import Foundation

enum Launchd {
    static let label = "dev.glidepath.run"

    /// The LaunchAgent dictionary. `binary` must be the stable path the user installed (not a build folder).
    /// One StartCalendarInterval entry per time, and per day when the days are not all of them (launchd reads a
    /// missing Weekday as every day).
    static func intervals(schedule: [ScheduleTime], days: ScheduleDays) -> [[String: Any]] {
        schedule.flatMap { time -> [[String: Any]] in
            let base: [String: Any] = ["Hour": time.hour, "Minute": time.minute]
            guard days != .all else { return [base] }
            return days.active.map { day -> [String: Any] in
                var entry = base
                entry["Weekday"] = day.launchd
                return entry
            }
        }
    }

    static func plist(binary: String, schedule: [ScheduleTime], days: ScheduleDays = .all, path: String,
                      logFile: String) -> [String: Any] {
        return [
            "Label": label,
            "ProgramArguments": [binary, "run", "--scheduled"],
            "StartCalendarInterval": intervals(schedule: schedule, days: days),
            "EnvironmentVariables": ["PATH": path],
            "StandardOutPath": logFile,
            "StandardErrorPath": logFile,
            "RunAtLoad": false,
        ]
    }

    static func data(binary: String, schedule: [ScheduleTime], days: ScheduleDays = .all, path: String,
                     logFile: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: plist(binary: binary, schedule: schedule, days: days, path: path, logFile: logFile),
            format: .xml, options: 0)
    }

    static let tendLabel = "dev.glidepath.tend"

    /// The tend job: one `glidepath tend` check every five minutes. Installed only while tending is on.
    static func tendPlist(binary: String, path: String, logFile: String) -> [String: Any] {
        [
            "Label": tendLabel,
            "ProgramArguments": [binary, "tend"],
            "StartInterval": 300,
            "EnvironmentVariables": ["PATH": path],
            "StandardOutPath": logFile,
            "StandardErrorPath": logFile,
            "RunAtLoad": false,
        ]
    }
}

/// Finds gitnexus for the launchd job. A job does not inherit the shell's PATH, so the directory it lives in is added
/// to the job's PATH when `init` or `init --refresh` finds it.
enum GitNexus {
    /// Where gitnexus is commonly installed, after PATH itself.
    static func commonDirectories(home: String) -> [String] {
        [home + "/Library/pnpm", home + "/.local/share/pnpm", home + "/.npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// The full path of gitnexus: on `path`, then in the common folders, then in npm's global bin. nil when none has it.
    static func find(path: String?, home: String) -> String? {
        if let found = Shell.find("gitnexus", path: path) { return found }
        for dir in commonDirectories(home: home) where FileManager.default.isExecutableFile(atPath: dir + "/gitnexus") {
            return dir + "/gitnexus"
        }
        guard let npm = Shell.find("npm", path: path) else { return nil }
        let prefix = Shell.run(npm, ["prefix", "-g"], timeout: 30).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = prefix + "/bin/gitnexus"
        return prefix.isEmpty || !FileManager.default.isExecutableFile(atPath: candidate) ? nil : candidate
    }

    /// `base` with the directory of `gitnexus` appended when it is not already listed. Appended, so the entries
    /// already there keep their order and precedence.
    static func addingDirectory(of gitnexus: String?, to base: String) -> String {
        guard let gitnexus else { return base }
        let dir = (gitnexus as NSString).deletingLastPathComponent
        let entries = base.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard !entries.contains(dir) else { return base }
        return base.isEmpty ? dir : base + ":" + dir
    }

    /// The PATH for the job: `base` plus gitnexus's directory when gitnexus can be found.
    static func jobPath(base: String, home: String) -> String {
        addingDirectory(of: find(path: base, home: home), to: base)
    }
}

/// Stop ends a running check. A pid file counts only while its lock is held, and only when it names a glidepath process
/// other than this one, so a pid left behind by a crash, or reused by the OS, is never signalled. Stop signals that one
/// process; the check, on SIGTERM, ends its own process group (the sessions it started) unless it is inside a merge or a
/// push, which it finishes first.
enum Stop {
    /// Which checks were signalled.
    struct Signalled: Equatable {
        var sweep = false
        var tend = false
        var any: Bool { sweep || tend }
    }

    /// Sends SIGTERM to the process named in `pidFile` while `lock` is held, then removes the pid file. True when it
    /// signalled. `isOurs` is for tests, which cannot start a binary named glidepath.
    static func signal(pidFile: String, lock: String, isOurs: (pid_t) -> Bool = isGlidepath) -> Bool {
        guard RunLock.isHeld(lock), let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1, pid != getpid(),
              isOurs(pid) else { return false }
        let sent = kill(pid, SIGTERM) == 0
        try? FileManager.default.removeItem(atPath: pidFile)
        return sent
    }

    /// Whether `pid` runs a binary named glidepath.
    static func isGlidepath(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return (String(cString: buffer) as NSString).lastPathComponent == "glidepath"
    }

    /// Signals the running sweep or dry run, and the running tend check.
    static func signal(_ paths: Paths, isOurs: (pid_t) -> Bool = isGlidepath) -> Signalled {
        Signalled(sweep: signal(pidFile: paths.pidFile, lock: paths.lockFile, isOurs: isOurs),
                  tend: signal(pidFile: paths.tendPidFile, lock: paths.tendLockFile, isOurs: isOurs))
    }

    /// Waits up to `within` seconds for the signalled checks to end, then tidies after each one that did: a stopped sweep's
    /// run file (`run`) is recorded as finished, since a stopped run is not a failed one, and a stopped tend check's working
    /// line is cleared from its snapshot. Returns the checks still running.
    static func settle(_ paths: Paths, _ signalled: Signalled, run: String?, within: TimeInterval) -> Signalled {
        let deadline = Date().addingTimeInterval(within)
        func ended(_ lock: String) -> Bool {
            while RunLock.isHeld(lock) {
                guard Date() < deadline else { return false }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return true
        }
        var running = Signalled()
        if signalled.sweep {
            if ended(paths.lockFile) {
                if let run {
                    try? RunStore(paths: paths).mutate(run) { if $0.finished == nil { $0.finish(at: Date(), error: nil) } }
                }
            } else {
                running.sweep = true
            }
        }
        if signalled.tend {
            if ended(paths.tendLockFile) {
                let store = TendStore(paths: paths)
                if var approach = store.loadApproach(), approach.working != nil {
                    approach.working = nil
                    try? store.saveApproach(approach)
                }
            } else {
                running.tend = true
            }
        }
        return running
    }

    // MARK: In the check

    /// [0] is how deep the check is in `finishing` sections; [1] is set when a stop came in during one. Raw memory, since
    /// the signal handler reads it.
    private static let flags: UnsafeMutablePointer<sig_atomic_t> = {
        let p = UnsafeMutablePointer<sig_atomic_t>.allocate(capacity: 2)
        p.initialize(repeating: 0, count: 2)
        return p
    }()
    private static let depth = NSLock()

    /// Called by a check right after it takes its lock. Any pid file there is stale, since the lock is this process's
    /// now, so it is replaced. Away from a terminal (launchd, the app) the check leads a process group of its own, so a
    /// stop ends the sessions it started too. Run by hand in a terminal it stays in the terminal's group, so Ctrl-C still
    /// reaches it, and a stop ends only this process.
    static func register(pidFile: String) {
        try? FileManager.default.removeItem(atPath: pidFile)
        if tcgetpgrp(STDIN_FILENO) != getpgrp(), setpgid(0, 0) != 0 {
            eprint("could not start a process group (errno \(errno)); Stop ends only this process")
        }
        _ = flags
        _ = Darwin.signal(SIGTERM) { _ in
            if Stop.flags[0] > 0 { Stop.flags[1] = 1 } else { Stop.halt() }
        }
        try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)
    }

    /// Runs `body` without being stopped part way: a SIGTERM that comes in during it takes effect when it returns. For a
    /// merge or a push and the record of it, so a stop never leaves one done on GitHub and missing on disk.
    static func finishing<T>(_ body: () throws -> T) rethrows -> T {
        depth.lock()
        flags[0] += 1
        depth.unlock()
        defer {
            depth.lock()
            flags[0] -= 1
            let stop = flags[0] == 0 && flags[1] != 0
            depth.unlock()
            if stop { halt() }
        }
        return try body()
    }

    /// Ends this process, and its group when it leads one. Async-signal-safe.
    private static func halt() -> Never {
        _ = Darwin.signal(SIGTERM, SIG_DFL)
        if getpgrp() == getpid() { kill(0, SIGTERM) }
        _exit(143)
    }
}

/// Pause is a marker file, so the launchd job and the menu bar app agree without talking to each other. Its lines are
/// "paused <time>" and, for a timed pause, "until <time>".
enum Pause {
    /// True while the marker exists. A timed pause ends on its own: once `until` has passed, the marker is removed.
    static func isPaused(_ paths: Paths, now: Date = Date()) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.pausedFile) else { return false }
        if let until = until(paths), now >= until {
            try? fm.removeItem(atPath: paths.pausedFile)
            return false
        }
        return true
    }

    /// When the pause started, read from the marker file. nil when not paused or unreadable.
    static func since(_ paths: Paths) -> Date? { field("paused", paths) }

    /// When a timed pause ends. nil for an open-ended pause.
    static func until(_ paths: Paths) -> Date? { field("until", paths) }

    private static func field(_ key: String, _ paths: Paths) -> Date? {
        guard let text = try? String(contentsOfFile: paths.pausedFile, encoding: .utf8) else { return nil }
        let prefix = key + " "
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return ISO8601DateFormatter().date(from: String(line.dropFirst(prefix.count)))
    }

    /// Whether setup pauses the schedule. A job that is already installed keeps its state; with no job yet, the first
    /// install starts paused, so the schedule stays off until the user turns it on.
    static func pausesOnSetup(jobInstalled: Bool) -> Bool {
        !jobInstalled
    }

    /// Whether "Post nothing yet" pauses the schedule. Only a job this setup created is paused; an existing job keeps its state.
    static func pausesOnPostNothing(createdJob: Bool) -> Bool {
        createdJob
    }

    /// Pauses, optionally until `until`, and signals what runs now. A check that is just starting reads the marker again
    /// once it holds its lock, so it stops itself.
    static func pause(_ paths: Paths, until: Date? = nil, isOurs: (pid_t) -> Bool = Stop.isGlidepath) throws -> Stop.Signalled {
        try set(true, paths, until: until)
        return Stop.signal(paths, isOurs: isOurs)
    }

    /// Pauses, optionally until `until`, or resumes. Resuming removes the marker.
    static func set(_ paused: Bool, _ paths: Paths, until: Date? = nil) throws {
        let fm = FileManager.default
        if paused {
            try fm.createDirectory(atPath: paths.stateDir, withIntermediateDirectories: true)
            let iso = ISO8601DateFormatter()
            var text = "paused \(iso.string(from: Date()))\n"
            if let until { text += "until \(iso.string(from: until))\n" }
            try Data(text.utf8).write(to: URL(fileURLWithPath: paths.pausedFile))
        } else if fm.fileExists(atPath: paths.pausedFile) {
            try fm.removeItem(atPath: paths.pausedFile)
        }
    }
}
