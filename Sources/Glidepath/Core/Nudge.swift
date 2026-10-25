import Foundation

/// When a reviewer has waited long enough for a ping. Only Monday to Friday hours count, so a weekend does not age a request.
enum Nudge {
    static func weekdayHours(from: Date, to: Date, calendar: Calendar = .current) -> Double {
        guard to > from else { return 0 }
        var seconds: TimeInterval = 0
        var day = calendar.startOfDay(for: from)
        while day < to {
            if let interval = calendar.dateInterval(of: .day, for: day), (2...6).contains(calendar.component(.weekday, from: day)) {
                let start = max(from, interval.start)
                let end = min(to, interval.end)
                if end > start { seconds += end.timeIntervalSince(start) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return seconds / 3600
    }

    /// The reviewers a PR has waited on for more than `hours` weekday hours, in request order. None once approved.
    static func waiting(_ pr: OpenPR, now: Date, hours: Int, calendar: Calendar = .current) -> [(login: String, hours: Int)] {
        guard !pr.approved else { return [] }
        return pr.requested.compactMap { login in
            guard let at = pr.requestedAt[login] else { return nil }
            let waited = weekdayHours(from: at, to: now, calendar: calendar)
            return waited > Double(hours) ? (login: login, hours: Int(waited)) : nil
        }
    }
}
