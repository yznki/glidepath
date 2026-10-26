import Foundation

/// The hours tend stays off the Claude usage: a time range that may cross midnight, and whole days.
struct QuietHours: Equatable {
    var start: ScheduleTime
    var end: ScheduleTime
    var days: Set<Weekday>

    /// "22:00-07:00,sat,sun": the range, then the days that are quiet all day. Nil when the text does not read.
    static func parse(_ text: String) -> QuietHours? {
        let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let range = parts[0].components(separatedBy: "-")
        guard range.count == 2, let start = ScheduleTime(range[0]), let end = ScheduleTime(range[1]) else { return nil }
        var days = Set<Weekday>()
        for name in parts.dropFirst() {
            guard let day = Weekday.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
            days.insert(day)
        }
        return QuietHours(start: start, end: end, days: days)
    }

    /// The value as config.toml writes it.
    var text: String {
        let range = start.text + "-" + end.text
        return ([range] + Weekday.allCases.filter { days.contains($0) }.map(\.name)).joined(separator: ",")
    }

    /// True on a quiet day, or at a time in the range. The range is [start, end) and wraps midnight; equal start and
    /// end mean no range.
    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        // Calendar's weekday runs Sunday = 1; Weekday.launchd runs Sunday = 0.
        if let day = Weekday.allCases.first(where: { $0.launchd == (c.weekday ?? 1) - 1 }), days.contains(day) {
            return true
        }
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let from = start.minutes
        let to = end.minutes
        if from == to { return false }
        return from < to ? (from <= now && now < to) : (now >= from || now < to)
    }

    /// The first quarter hour on the clock after `date` that is quiet, looking eight days ahead. Nil when none is.
    func nextStart(after date: Date, calendar: Calendar) -> Date? {
        let step: TimeInterval = 900
        let first = (date.timeIntervalSince1970 / step).rounded(.down) * step + step
        for k in 0..<(8 * 96) {
            let t = Date(timeIntervalSince1970: first + Double(k) * step)
            if contains(t, calendar: calendar) { return t }
        }
        return nil
    }
}

/// One rate-limit window as Claude reported it in a stream-json transcript.
struct UsageWindow: Codable, Equatable {
    var type: String
    /// 0 to 1, as Claude reports it.
    var utilization: Double
    var resetsAt: Date?
    /// When the event was read.
    var seen: Date
}

/// The newest window of each type, kept in `stateDir/usage.json`.
struct UsageState: Codable, Equatable {
    var windows: [String: UsageWindow] = [:]

    /// The saved state, or an empty one when the file is missing or unreadable.
    static func load(_ paths: Paths) -> UsageState {
        guard let data = FileManager.default.contents(atPath: file(paths)),
              let state = try? RunStore.decoder().decode(UsageState.self, from: data) else { return UsageState() }
        return state
    }

    func save(_ paths: Paths) throws {
        try FileManager.default.createDirectory(atPath: paths.stateDir, withIntermediateDirectories: true)
        try RunStore.encoder().encode(self).write(to: URL(fileURLWithPath: UsageState.file(paths)), options: .atomic)
    }

    /// Keeps each type's window, newest `seen` wins.
    mutating func record(_ new: [UsageWindow]) {
        for w in new {
            if let old = windows[w.type], old.seen > w.seen { continue }
            windows[w.type] = w
        }
    }

    private static func file(_ paths: Paths) -> String { paths.stateDir + "/usage.json" }
}

/// How much of the Claude usage is spent now, against the share kept for the user. Read from the busiest live window.
struct UsageReading: Equatable {
    /// 0 to 100.
    var used: Int
    /// The percent `tend.usage_reserve` keeps for the user.
    var reserve: Int
    var resetsAt: Date?

    /// Past this, tend holds its work back for the reset.
    var overReserve: Bool { used >= 100 - reserve }
}

extension UsageState {
    /// The busiest live window against `reserve`. Nil when no window is live.
    func reading(reserve: Int, now: Date) -> UsageReading? {
        guard let w = windows.values.filter({ UsageGuard.isLive($0, now: now) }).max(by: { $0.utilization < $1.utilization })
        else { return nil }
        return UsageReading(used: Int((w.utilization * 100).rounded()), reserve: reserve, resetsAt: w.resetsAt)
    }
}

enum WorkClass: String, Codable, Equatable { case urgent, normal, deferred }

enum SpendDecision: Equatable {
    case now
    case wait(until: Date?, reason: String)
    case stop(String)
}

/// Decides whether tend may spend Claude usage now, from the rate-limit windows Claude reported.
enum UsageGuard {
    /// The reason deferred work gives while it waits for quiet hours. The app tells this wait from a usage wait by it.
    static let quietReason = "Waiting for quiet hours"

    /// The rate-limit windows in a stream-json transcript: each `rate_limit_event` line, seen at `now`.
    static func events(stream: String, now: Date) -> [UsageWindow] {
        stream.components(separatedBy: "\n").flatMap { line -> [UsageWindow] in
            guard line.contains("\"rate_limit_event\""), let obj = Transcript.json(line),
                  obj["type"] as? String == "rate_limit_event",
                  let info = obj["rate_limit_info"] as? [String: Any] else { return [] }
            func window(_ type: String, _ fields: [String: Any]) -> UsageWindow? {
                guard let utilization = (fields["utilization"] as? NSNumber)?.doubleValue else { return nil }
                let resets = (fields["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                return UsageWindow(type: type, utilization: utilization, resetsAt: resets, seen: now)
            }
            // Claude Code 2.1.310 nests each window under unifiedWindows; the flat form is the older shape.
            if let windows = info["unifiedWindows"] as? [String: [String: Any]] {
                return windows.sorted { $0.key < $1.key }.compactMap { window($0.key, $0.value) }
            }
            guard let type = info["rateLimitType"] as? String else { return [] }
            return window(type, info).map { [$0] } ?? []
        }
    }

    /// The `result` of the transcript's `result` line, which is the session's final answer.
    static func resultText(stream: String) -> String? {
        for line in stream.components(separatedBy: "\n").reversed() where line.contains("\"result\"") {
            if let obj = Transcript.json(line), obj["type"] as? String == "result", let text = obj["result"] as? String {
                return text
            }
        }
        return nil
    }

    /// Whether work of class `cls` may spend now. Deferred work waits for quiet hours. Once a live window is past
    /// `100 - reserve` percent, urgent work stops and the rest waits for the reset.
    /// ponytail: no per-task estimate (tokens to utilization is not known); add once History has calibrated it.
    static func decide(_ cls: WorkClass, _ usage: UsageState, reserve: Int, quiet: QuietHours, now: Date,
                       calendar: Calendar = .current) -> SpendDecision {
        if cls == .deferred && !quiet.contains(now, calendar: calendar) {
            return .wait(until: quiet.nextStart(after: now, calendar: calendar), reason: quietReason)
        }
        let over = usage.windows.values.filter { isLive($0, now: now) && $0.utilization * 100 >= Double(100 - reserve) }
        guard !over.isEmpty else { return .now }
        let resets = over.compactMap(\.resetsAt).max()
        let when = resets.map { " · resets \(clock($0, calendar: calendar))" } ?? ""
        if cls == .urgent { return .stop("Usage reserve reached" + when) }
        return .wait(until: resets, reason: "Paused for usage" + when)
    }

    /// A window is live until its reset. One with no reset time is live for its length after it was seen.
    static func isLive(_ w: UsageWindow, now: Date) -> Bool {
        if let resets = w.resetsAt { return resets > now }
        let length: TimeInterval = w.type == "seven_day" ? 7 * 86_400 : 5 * 3_600
        return now.timeIntervalSince(w.seen) < length
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
