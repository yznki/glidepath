import XCTest
@testable import Glidepath

final class ScheduleTests: XCTestCase {
    let home = "/fake/home"
    let base = Config(schedule: [ScheduleTime("07:00")!, ScheduleTime("19:00")!], limits: Limits(), repos: [])

    private func parse(_ days: String) throws -> Config {
        try Config.parse("schedule = [\"07:00\"]\n" + days + "\n", home: home)
    }

    // MARK: Config `days`

    func testDaysDefaultsToAllWhenAbsent() throws {
        XCTAssertEqual(try parse("").days, .all)
        XCTAssertEqual(Config.defaultSchedule.count, 3)
    }

    func testDaysParsesPresetsAndLists() throws {
        XCTAssertEqual(try parse("days = \"weekdays\"").days, .weekdays)
        XCTAssertEqual(try parse("days = \"all\"").days, .all)
        XCTAssertEqual(try parse("days = [\"sat\", \"mon\"]").days, .custom([.mon, .sat]))
    }

    func testInvalidDaysThrow() {
        XCTAssertThrowsError(try parse("days = \"never\""))
        XCTAssertThrowsError(try parse("days = [\"funday\"]"))
        XCTAssertThrowsError(try parse("days = []"))
        XCTAssertThrowsError(try parse("days = 3"))
    }

    func testRenderWritesDaysOnlyWhenNotAll() throws {
        XCTAssertFalse(base.render().contains("days ="), "the default keeps existing golden output")
        var weekdays = base
        weekdays.days = .weekdays
        XCTAssertTrue(weekdays.render().contains("days = \"weekdays\"\n"))
        var custom = base
        custom.days = .custom([.fri, .mon])
        XCTAssertTrue(custom.render().contains("days = [\"mon\", \"fri\"]\n"))
        for config in [weekdays, custom] {
            XCTAssertEqual(try Config.parse(config.render(), home: home).days, config.days)
        }
    }

    func testWeekdayNumbersMatchLaunchd() {
        XCTAssertEqual(Weekday.sun.launchd, 0)
        XCTAssertEqual(Weekday.mon.launchd, 1)
        XCTAssertEqual(Weekday.sat.launchd, 6)
        XCTAssertEqual(ScheduleDays.weekdays.active, [.mon, .tue, .wed, .thu, .fri])
    }

    // MARK: Launchd intervals

    private func intervals(_ days: ScheduleDays) throws -> [[String: Int]] {
        let data = try Launchd.data(binary: "/opt/glidepath", schedule: base.schedule, days: days,
                                    path: "/usr/bin", logFile: "/tmp/log")
        let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        return try XCTUnwrap(dict["StartCalendarInterval"] as? [[String: Int]])
    }

    func testAllDaysKeepsOneEntryPerTimeWithoutWeekday() throws {
        let entries = try intervals(.all)
        XCTAssertEqual(entries, [["Hour": 7, "Minute": 0], ["Hour": 19, "Minute": 0]])
    }

    func testWeekdaysGivesFiveEntriesPerTime() throws {
        let entries = try intervals(.weekdays)
        XCTAssertEqual(entries.count, 2 * 5)
        XCTAssertEqual(entries.filter { $0["Hour"] == 7 }.compactMap { $0["Weekday"] }, [1, 2, 3, 4, 5])
        XCTAssertTrue(entries.allSatisfy { $0["Minute"] == 0 })
    }

    func testCustomDaysUseLaunchdNumbering() throws {
        let entries = try intervals(.custom([.sun, .wed]))
        // Days go in week order, Monday first, so Sunday (launchd 0) comes after Wednesday (3).
        XCTAssertEqual(entries.map { [$0["Hour"], $0["Weekday"]] }, [[7, 3], [7, 0], [19, 3], [19, 0]])
    }

    // MARK: ScheduleEditor

    func testAddTimeRoundsToQuarterHourAndSorts() throws {
        let added = try ScheduleEditor.addTime(base, hour: 12, minute: 7)
        XCTAssertEqual(added.schedule.map(\.text), ["07:00", "12:00", "19:00"])
        XCTAssertEqual(try ScheduleEditor.addTime(base, hour: 12, minute: 8).schedule.map(\.text),
                       ["07:00", "12:15", "19:00"])
        XCTAssertEqual(try ScheduleEditor.addTime(base, hour: 23, minute: 53).schedule.last?.text, "23:45")
    }

    func testDuplicateAndInvalidTimes() throws {
        XCTAssertEqual(try ScheduleEditor.addTime(base, hour: 7, minute: 0), base, "a duplicate changes nothing")
        XCTAssertEqual(try ScheduleEditor.addTime(base, hour: 7, minute: 6), base, "rounds onto an existing time")
        XCTAssertThrowsError(try ScheduleEditor.addTime(base, hour: 24, minute: 0))
        XCTAssertThrowsError(try ScheduleEditor.addTime(base, hour: 9, minute: 60))
    }

    func testRemoveKeepsOneTime() throws {
        let removed = try ScheduleEditor.removeTime(base, ScheduleTime("19:00")!)
        XCTAssertEqual(removed.schedule.map(\.text), ["07:00"])
        XCTAssertThrowsError(try ScheduleEditor.removeTime(removed, ScheduleTime("07:00")!))
    }

    func testMoveRoundsAndRefusesDuplicates() throws {
        let moved = try ScheduleEditor.moveTime(base, from: ScheduleTime("07:00")!, hour: 8, minute: 20)
        XCTAssertEqual(moved.schedule.map(\.text), ["08:15", "19:00"])
        XCTAssertEqual(try ScheduleEditor.moveTime(base, from: ScheduleTime("07:00")!, hour: 19, minute: 0), base)
    }

    func testDaysAndLimitsValidate() throws {
        XCTAssertThrowsError(try ScheduleEditor.setDays(base, .custom([])))
        XCTAssertEqual(try ScheduleEditor.setDays(base, .weekdays).days, .weekdays)
        XCTAssertThrowsError(try ScheduleEditor.setLimits(base, prs: 0, lines: 500))
        XCTAssertThrowsError(try ScheduleEditor.setLimits(base, prs: 5, lines: 0))
        XCTAssertThrowsError(try ScheduleEditor.setLimits(base, prs: 5, lines: 100_001))
        let set = try ScheduleEditor.setLimits(base, prs: 4, lines: 8000)
        XCTAssertEqual(set.limits.maxPRsPerRun, 4)
        XCTAssertEqual(set.limits.maxChangedLines, 8000)
    }

    // MARK: Next sweep

    func testNextSweepSkipsDaysNotInTheSet() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        // 2026-10-19 is a Monday. The next Saturday sweep after Monday 08:00 is 24 Oct at 07:00.
        let monday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
        let next = try XCTUnwrap(Store.nextSweep(schedule: [ScheduleTime("07:00")!], days: .custom([.sat]), after: monday))
        XCTAssertEqual(cal.component(.day, from: next), 24)
        XCTAssertEqual(cal.component(.hour, from: next), 7)
    }

    // MARK: This week

    private func pr(_ n: Int, _ verdict: Verdict?, carried: Date? = nil, tokens: Int = 0) -> PRState {
        PRState(n: n, author: "ana", title: nil, stage: .post, active: false, verdict: verdict, reason: nil,
                tokens: tokens, carriedFrom: carried)
    }

    func testWeekStatsCountsFreshRowsSinceMonday() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let since = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let earlier = since.addingTimeInterval(-3600)
        let runs = [
            RunState(id: "a", started: since.addingTimeInterval(60), finished: nil,
                     repos: [RepoState(slug: "a/b", prs: [pr(1, .approve), pr(2, .changes), pr(3, .skipped)])],
                     tokens: 1_200_000, error: nil),
            // A carried row is the same PR decided earlier: it is not counted again.
            RunState(id: "b", started: since.addingTimeInterval(7200), finished: nil,
                     repos: [RepoState(slug: "a/b", prs: [pr(2, .changes, carried: since), pr(4, .changes)])],
                     tokens: 900_000, error: nil),
            RunState(id: "old", started: earlier, finished: nil,
                     repos: [RepoState(slug: "a/b", prs: [pr(9, .approve)])], tokens: 5, error: nil),
        ]
        let stats = WeekStats.compute(runs: runs, since: since)
        XCTAssertEqual(stats, WeekStats(reviews: 3, needChanges: 2, tokens: 2_100_000))
    }

    func testWeekStartIsMondayMidnight() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let sunday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 15)))
        let start = try XCTUnwrap(WeekStats.weekStart(of: sunday, calendar: cal))
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: start),
                       DateComponents(year: 2026, month: 10, day: 19, hour: 0, minute: 0))
    }
}
