import Foundation

/// What the morning briefing reports since the last one.
struct Briefing: Codable, Equatable {
    var at: Date
    var landed: [String]
    var blocked: [String]
    var rounds: Int
    var threads: Int
    var councils: Int
    var tokens: Int
    var dismissedAt: Date? = nil
}

extension Briefing {
    /// The briefing for the stretch since `since`: what landed, what waits on the user, and what the runs since then did.
    static func compose(since: Date, now: Date, runs: [RunState], landed: [TendLanded], needs: [NeedsItem]) -> Briefing {
        let recent = runs.filter { $0.started >= since && $0.kind == "tend" }
        return Briefing(
            at: now,
            landed: landed.filter { $0.at >= since }.map { "#\($0.n) \($0.title)" },
            blocked: blockedLines(needs),
            rounds: recent.filter { $0.tendAction != nil && !["self-review", "consolidated"].contains($0.tendAction ?? "") }.count,
            threads: recent.reduce(0) { $0 + ($1.tendThreads?.count ?? 0) },
            councils: recent.reduce(0) { $0 + ($1.council?.count ?? 0) },
            tokens: recent.reduce(0) { $0 + $1.tokens })
    }

    /// The rows that wait on the user, as the briefing lists them: "#n · detail" for each held, stuck, call or blocked need.
    static func blockedLines(_ needs: [NeedsItem]) -> [String] {
        needs.filter { ["held", "stuck", "call", "blocked"].contains($0.kind) }.map { "#\($0.n) · \($0.detail)" }
    }

    /// Due when `time` has passed today, it has not yet been shown today, and today is one of the `days`.
    static func isDue(now: Date, last: Date?, time: ScheduleTime, days: ScheduleDays, calendar: Calendar = .current) -> Bool {
        guard let todayTime = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) else { return false }
        guard let today = Weekday(rawValue: (calendar.component(.weekday, from: now) + 5) % 7),
              days.active.contains(today) else { return false }
        return now >= todayTime && (last.map { $0 < todayTime } ?? true)
    }
}
