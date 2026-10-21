import Foundation

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

    /// Writes the config atomically, then rewrites and reloads the launchd job with the new schedule and days.
    static func save(_ config: Config, paths: Paths) throws {
        try ConfigEditor.save(config, paths: paths)
        let base = Runner.jobPath(paths) ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        try InitCommand.installJob(paths: paths, config: config, binary: InitCommand.binaryPath(),
                                   path: GitNexus.jobPath(base: base, home: paths.home))
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
