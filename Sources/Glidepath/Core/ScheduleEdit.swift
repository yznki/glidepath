import Foundation

/// Whether a schedule save reinstalls the launchd job now. Reinstalling boots the job out, which would stop a sweep that
/// is running, so while the run lock is held the config is written and the reinstall waits.
enum ScheduleSave {
    enum Decision: Equatable {
        case writeAndReinstall
        case writeOnly(deferred: Bool)
    }

    static func decision(lockHeld: Bool) -> Decision {
        lockHeld ? .writeOnly(deferred: true) : .writeAndReinstall
    }
}

/// Keyboard nudges for a sweep pin, as pure functions. Times are minutes of the day; a pin stays between 00:00 and 23:45.
enum PinNudge {
    static let firstMinute = 0
    static let lastMinute = 23 * 60 + 45
    static let quarter = 15

    /// The time a pin moves to by `minutes` (15, 60, or their negatives). It is clamped to the day, and a move that
    /// lands on a listed time skips past it, one quarter hour at a time, in the same direction. Nil when the pin cannot
    /// move: it is already at the day's edge, or every step that way is taken.
    static func target(from time: ScheduleTime, by minutes: Int, among times: [ScheduleTime]) -> ScheduleTime? {
        let start = minute(of: time)
        let step = minutes < 0 ? -quarter : quarter
        var m = min(max(start + minutes, firstMinute), lastMinute)
        guard m != start else { return nil }
        let taken = Set(times.map(minute(of:)))
        while taken.contains(m) {
            m += step
            guard (firstMinute...lastMinute).contains(m) else { return nil }
        }
        return ScheduleTime(minuteOfDay: m)
    }

    static func minute(of time: ScheduleTime) -> Int { time.hour * 60 + time.minute }
}

/// One pin's move: the time it has on disk and the time the keys have moved it to.
struct PinMove: Equatable {
    let from: ScheduleTime
    let to: ScheduleTime

    /// The draft left after `saved` has been written. Nothing is left when the keys have not moved the pin since the
    /// save began. Otherwise the pin's time on disk is now `saved.to`, so the rest of the move starts there.
    static func settle(_ draft: PinMove?, saved: PinMove) -> PinMove? {
        guard let draft else { return nil }
        if draft == saved { return nil }
        return PinMove(from: saved.to, to: draft.to)
    }
}

extension ScheduleTime {
    /// The time for a minute of the day, 0 to 1439.
    init?(minuteOfDay minute: Int) {
        guard (0..<1440).contains(minute) else { return nil }
        self.init(String(format: "%02d:%02d", minute / 60, minute % 60))
    }
}

/// Edits to the schedule and the per-sweep limits, made from the Schedule section. Each function is pure and returns a
/// new `Config`, or throws `ConfigError`. `save` is the only one that writes, and it reinstalls the launchd job.
enum ScheduleEditor {
    /// Schedule times are kept on this step.
    static let step = 15
    /// The most lines per PR the window allows.
    static let maxLinesPerPR = 100_000

    /// Adds a time, rounded to 15 minutes. A time already listed changes nothing.
    static func addTime(_ config: Config, hour: Int, minute: Int) throws -> Config {
        let time = try rounded(hour: hour, minute: minute)
        guard !config.schedule.contains(time) else { return config }
        var out = config
        out.schedule = sorted(config.schedule + [time])
        return out
    }

    /// Removes a time. The last one stays: a config needs at least one sweep.
    static func removeTime(_ config: Config, _ time: ScheduleTime) throws -> Config {
        guard config.schedule.contains(time) else { return config }
        guard config.schedule.count > 1 else { throw ConfigError(message: "Keep at least one sweep time.") }
        var out = config
        out.schedule = config.schedule.filter { $0 != time }
        return out
    }

    /// Moves a time to a new hour and minute, rounded to 15 minutes. Onto a time already listed, nothing changes.
    static func moveTime(_ config: Config, from time: ScheduleTime, hour: Int, minute: Int) throws -> Config {
        let target = try rounded(hour: hour, minute: minute)
        guard config.schedule.contains(time), !config.schedule.contains(target) else { return config }
        var out = config
        out.schedule = sorted(config.schedule.filter { $0 != time } + [target])
        return out
    }

    /// Replaces the whole list of sweep times, sorted and without duplicates. Used to undo a schedule change.
    static func setSchedule(_ config: Config, _ times: [ScheduleTime]) throws -> Config {
        guard !times.isEmpty else { throw ConfigError(message: "Keep at least one sweep time.") }
        var out = config
        out.schedule = sorted(times)
        return out
    }

    static func setDays(_ config: Config, _ days: ScheduleDays) throws -> Config {
        if case .custom(let set) = days, set.isEmpty {
            throw ConfigError(message: "Keep at least one day on.")
        }
        var out = config
        out.days = days
        return out
    }

    /// PRs per sweep and lines per PR, both positive. Lines stop at `maxLinesPerPR`.
    static func setLimits(_ config: Config, prs: Int, lines: Int) throws -> Config {
        guard prs > 0 else { throw ConfigError(message: "PRs per sweep must be at least 1.") }
        guard (1...maxLinesPerPR).contains(lines) else {
            throw ConfigError(message: "Lines per PR must be between 1 and \(maxLinesPerPR).")
        }
        var out = config
        out.limits.maxPRsPerRun = prs
        out.limits.maxChangedLines = lines
        return out
    }

    /// Writes the config atomically, then rewrites and reloads the launchd job with the new schedule and days, unless a
    /// sweep holds the run lock. Returns true when the reinstall was deferred.
    @discardableResult
    static func save(_ config: Config, paths: Paths) throws -> Bool {
        try ConfigEditor.save(config, paths: paths)
        switch ScheduleSave.decision(lockHeld: RunLock.isHeld(paths.lockFile)) {
        case .writeAndReinstall:
            try installJob(config, paths: paths)
            return false
        case .writeOnly(let deferred):
            return deferred
        }
    }

    /// Rewrites and reloads the job for `config` as it is on disk now.
    static func installJob(_ config: Config, paths: Paths) throws {
        try InitCommand.installJob(paths: paths, config: config,
                                   binary: InitCommand.stableBinary(runningBinary: InitCommand.binaryPath()),
                                   path: InitCommand.jobPath(paths: paths))
    }

    /// True when a job is installed and the file on disk is not what config.toml would write now. False with no job
    /// (nothing to reconcile, so a fresh install or an uninstall is left alone) or with no readable config.
    static func jobNeedsReinstall(_ paths: Paths) -> Bool {
        guard FileManager.default.fileExists(atPath: paths.plistFile), let config = try? Config.load(paths) else {
            return false
        }
        return !InitCommand.jobIsCurrent(paths: paths, config: config,
                                         binary: InitCommand.stableBinary(runningBinary: InitCommand.binaryPath()),
                                         path: InitCommand.jobPath(paths: paths))
    }

    // MARK: Helpers

    /// A valid time of day, rounded up to the next quarter hour. 23:53 becomes 23:45 rather than passing midnight.
    static func rounded(hour: Int, minute: Int) throws -> ScheduleTime {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ConfigError(message: "\(hour):\(minute) is not a time of day")
        }
        let total = min((hour * 60 + minute + step / 2) / step * step, 23 * 60 + 45)
        let text = String(format: "%02d:%02d", total / 60, total % 60)
        guard let time = ScheduleTime(text) else { throw ConfigError(message: "\(text) is not a time of day") }
        return time
    }

    private static func sorted(_ times: [ScheduleTime]) -> [ScheduleTime] {
        Array(Set(times)).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
}
