import Foundation

extension ScheduleTime {
    /// Minutes after midnight, 0 to 1439.
    var minutes: Int { hour * 60 + minute }

    init(minutes: Int) {
        let m = ((minutes % 1440) + 1440) % 1440
        hour = m / 60
        minute = m % 60
    }
}

/// A schedule as a window: a start, an end and an interval. The config stores the list of times; the schedule dial
/// works in windows. Pure.
enum ScheduleWindow {
    /// The times from `start` to `end` inclusive, `every` minutes apart, in time-of-day order. An end before the start
    /// crosses midnight. Equal start and end give the one time. `every` is clamped to 15...240 minutes.
    static func times(start: ScheduleTime, end: ScheduleTime, every: Int) -> [ScheduleTime] {
        let step = min(max(every, 15), 240)
        let duration = (end.minutes - start.minutes + 1440) % 1440
        return stride(from: 0, through: duration, by: step)
            .map { ScheduleTime(minutes: start.minutes + $0) }
            .sorted { $0.minutes < $1.minutes }
    }

    /// The window that yields `times`, or nil when they are not evenly spaced, the spacing is outside 15...240
    /// minutes, or there are fewer than two.
    /// The window is the arc left when the largest gap between neighbours (wrapping past midnight) is cut out.
    /// Ties go to the gap that wraps midnight, so an evenly spaced day starts at its first time.
    static func infer(from times: [ScheduleTime]) -> (start: ScheduleTime, end: ScheduleTime, every: Int)? {
        let m = times.map(\.minutes).sorted()
        let k = m.count
        guard k >= 2 else { return nil }
        // Gap i runs from m[i] to the next time. The last gap wraps past midnight.
        func gap(_ i: Int) -> Int { i == k - 1 ? m[0] + 1440 - m[k - 1] : m[i + 1] - m[i] }
        var cut = k - 1
        for i in 0..<(k - 1) where gap(i) > gap(cut) { cut = i }
        let start = (cut + 1) % k
        let spans = (0..<(k - 1)).map { gap((start + $0) % k) }
        guard let every = spans.first, (15...240).contains(every), spans.allSatisfy({ $0 == every }) else { return nil }
        return (ScheduleTime(minutes: m[start]), ScheduleTime(minutes: m[cut]), every)
    }
}
