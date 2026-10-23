import Foundation

/// The schedule dial's window: a start, a span and an interval, in minutes. The config stores the list of sweep
/// times; the dial works in windows. `span` is 15...1440; 1440 is the whole day (start and end meet). Pure.
struct DialWindow: Equatable {
    static let day = 1440
    var start: Int
    var span: Int
    var every: Int

    /// The intervals that divide a day evenly, within 15...240. A whole-day window snaps to one, so the sweeps repeat
    /// at the same times each day.
    static let divisors = [15, 16, 18, 20, 24, 30, 32, 36, 40, 45, 48, 60, 72, 80, 90, 96, 120, 144, 160, 180, 240]

    init(start: Int, span: Int, every: Int) {
        self.start = ((start % DialWindow.day) + DialWindow.day) % DialWindow.day
        self.span = min(max(span, 15), DialWindow.day)
        let clamped = min(max(every, 15), 240)
        self.every = self.span == DialWindow.day
            ? DialWindow.divisors.min { abs($0 - clamped) < abs($1 - clamped) } ?? clamped
            : clamped
    }

    /// The minute the arc ends on (the end knob). Equals `start` for the whole day.
    var end: Int { (start + span) % DialWindow.day }

    /// The whole day: the sweeps go round the dial once.
    var isFullDay: Bool { span == DialWindow.day }

    /// The sweep times the window yields. A whole day stops one step before `start`, so the first sweep is not repeated.
    var times: [ScheduleTime] {
        let last = isFullDay ? start - 15 : start + span
        return ScheduleWindow.times(start: ScheduleTime(minutes: start), end: ScheduleTime(minutes: last), every: every)
    }

    /// The window with the start knob moved to `minute`. The end stays where it is.
    func movedStart(to minute: Int) -> DialWindow {
        let m = Self.normalized(minute)
        let span = (end - m + DialWindow.day) % DialWindow.day
        return DialWindow(start: m, span: span == 0 ? DialWindow.day : span, every: every)
    }

    /// The window with the end knob moved to `minute`. The start stays where it is. An end on the start is the whole day.
    func movedEnd(to minute: Int) -> DialWindow {
        let span = (Self.normalized(minute) - start + DialWindow.day) % DialWindow.day
        return DialWindow(start: start, span: span == 0 ? DialWindow.day : span, every: every)
    }

    private static func normalized(_ minute: Int) -> Int {
        ((minute % DialWindow.day) + DialWindow.day) % DialWindow.day
    }

    /// The window that yields `times`, or nil when `ScheduleWindow.infer` cannot describe them.
    static func from(times: [ScheduleTime]) -> DialWindow? {
        guard let inferred = ScheduleWindow.infer(from: times) else { return nil }
        let start = inferred.start.minutes
        let last = inferred.end.minutes
        // The last sweep plus one interval lands back on the start: the sweeps go all round the day.
        if (last + inferred.every) % DialWindow.day == start {
            return DialWindow(start: start, span: DialWindow.day, every: inferred.every)
        }
        return DialWindow(start: start, span: (last - start + DialWindow.day) % DialWindow.day, every: inferred.every)
    }

    /// The minute of the day a dial position (x right, y down, from the dial centre) points at, snapped to 15 min.
    /// Midnight is at the top.
    static func minute(dx: Double, dy: Double) -> Int {
        var fraction = (atan2(dy, dx) + Double.pi / 2) / (2 * Double.pi)
        fraction -= fraction.rounded(.down)
        let snapped = Int((fraction * Double(day) / 15).rounded()) * 15
        return snapped % day
    }
}

/// The day pills as a schedule setting. All seven is `.all`, Monday to Friday is `.weekdays`, anything else `.custom`.
enum DialDays {
    static func schedule(_ set: Set<Weekday>) -> ScheduleDays {
        if set == Set(Weekday.allCases.prefix(5)) { return .weekdays }
        if set == Set(Weekday.allCases) { return .all }
        return .custom(set)
    }

    static func set(_ days: ScheduleDays) -> Set<Weekday> { Set(days.active) }
}

/// Text for the dial and its strips.
enum DialFormat {
    /// "09:05" for a date, in the calendar's time zone.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "09:05" for a minute of the day.
    static func clock(minute: Int) -> String {
        let m = ((minute % DialWindow.day) + DialWindow.day) % DialWindow.day
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "45m", or "2h 41m" from an hour.
    static func interval(minutes: Int) -> String {
        let m = max(minutes, 0)
        return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
    }

    /// "850", "12k", "1.2M".
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}

/// The numbers under the dial. Tokens are the prototype's estimate: 9000 tokens per sweep, 4.3 weeks a month.
enum DialStats {
    static let tokensPerSweep = 9000
    static let weeksPerMonth = 4.3

    static func tokensPerMonth(perWeek: Int) -> Int {
        Int(Double(perWeek * tokensPerSweep) * weeksPerMonth)
    }

    /// True only when a budget is set (`monthly_tokens` > 0) and the estimate is over it.
    static func overBudget(tokens: Int, budget: Int) -> Bool {
        budget > 0 && tokens > budget
    }
}

/// The next sweeps, one after another, from `now`.
enum DialUpcoming {
    static func next(_ count: Int, after now: Date, times: [ScheduleTime], days: ScheduleDays,
                     calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var from = now
        while out.count < count, let next = ScheduleTimes.nextSweep(after: from, times: times, days: days, calendar: calendar) {
            out.append(next)
            from = next
        }
        return out
    }
}

/// "Until tomorrow": the first sweep time on the next sweep day after today. Nil when no day in the coming week is on.
enum DialPause {
    static func tomorrow(now: Date, times: [ScheduleTime], days: ScheduleDays, calendar: Calendar = .current) -> Date? {
        guard let first = times.min(by: { $0.minutes < $1.minutes }) else { return nil }
        let today = calendar.startOfDay(for: now)
        let on = Set(days.active.map(\.launchd))
        for offset in 1...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard on.contains(calendar.component(.weekday, from: day) - 1) else { continue }
            return calendar.date(bySettingHour: first.hour, minute: first.minute, second: 0, of: day)
        }
        return nil
    }
}

/// The four presets on the schedule dial.
struct DialPreset: Equatable {
    let key: String
    let name: String
    let detail: String
    let window: DialWindow
    let days: Set<Weekday>

    static let weekdays = Set(Weekday.allCases.prefix(5))
    static let everyDay = Set(Weekday.allCases)

    static let all: [DialPreset] = [
        DialPreset(key: "office", name: "Office hours", detail: "Weekdays 9–18 · 30 min",
                   window: DialWindow(start: 540, span: 540, every: 30), days: weekdays),
        DialPreset(key: "clock", name: "Around the clock", detail: "Every day · hourly",
                   window: DialWindow(start: 0, span: 1440, every: 60), days: everyDay),
        DialPreset(key: "night", name: "Night shift", detail: "Every day 20–04 · 45 min",
                   window: DialWindow(start: 1200, span: 480, every: 45), days: everyDay),
        DialPreset(key: "mornings", name: "Sharp mornings", detail: "Weekdays 7–11 · 15 min",
                   window: DialWindow(start: 420, span: 240, every: 15), days: weekdays),
    ]
}
