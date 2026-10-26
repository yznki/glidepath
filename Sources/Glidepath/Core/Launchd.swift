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

/// Pause is a marker file, so the launchd job and the menu bar app agree without talking to each other. Its lines are
/// "paused <time>" and, for a timed pause, "until <time>".
/// Stop: signals a running check's process group. A pid file counts only while its lock is held, so a pid left behind by a
/// crash is never signalled.
enum Stop {
    /// Sends SIGTERM to the process group named in `pidFile` while `lock` is held. True when it signalled.
    static func signal(pidFile: String, lock: String) -> Bool {
        guard RunLock.isHeld(lock), let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return false }
        return kill(-pid, SIGTERM) == 0
    }

    /// Stops a running sweep or dry run, and records `run` (its run file) as finished: a stopped run is not a failed one.
    static func sweep(_ paths: Paths, run: String?) -> Bool {
        guard signal(pidFile: paths.pidFile, lock: paths.lockFile) else { return false }
        if let run {
            try? RunStore(paths: paths).mutate(run) { if $0.finished == nil { $0.finish(at: Date(), error: nil) } }
        }
        return true
    }

    /// Stops a running tend check and the round it is in, and clears the round's working line from the snapshot it wrote.
    static func tend(_ paths: Paths) -> Bool {
        guard signal(pidFile: paths.tendPidFile, lock: paths.tendLockFile) else { return false }
        let store = TendStore(paths: paths)
        if var approach = store.loadApproach(), approach.working != nil {
            approach.working = nil
            try? store.saveApproach(approach)
        }
        return true
    }

    /// Stops both. True when either was running.
    static func all(_ paths: Paths, run: String?) -> Bool {
        let sweep = sweep(paths, run: run)
        let tend = tend(paths)
        return sweep || tend
    }
}

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
