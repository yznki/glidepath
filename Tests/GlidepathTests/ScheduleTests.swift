import XCTest
@testable import Glidepath

final class ScheduleTests: XCTestCase {
    let home = "/fake/home"
    let base = Config(schedule: [ScheduleTime("07:00")!, ScheduleTime("19:00")!], limits: Limits(), repos: [])

    private func parse(_ days: String) throws -> Config {
        try Config.parse("schedule = [\"07:00\"]\n" + days + "\n", home: home)
    }

    // MARK: Save while a sweep runs

    /// A save reinstalls the job only when no sweep holds the run lock; otherwise the config is written and the
    /// reinstall waits.
    func testSaveDefersTheReinstallWhileALockIsHeld() {
        XCTAssertEqual(ScheduleSave.decision(lockHeld: false), .writeAndReinstall)
        XCTAssertEqual(ScheduleSave.decision(lockHeld: true), .writeOnly(deferred: true))
    }

    // MARK: Config `days`

    func testDaysDefaultsToAllWhenAbsent() throws {
        XCTAssertEqual(try parse("").days, .all)
        XCTAssertEqual(Config.defaultSchedule.count, 4)
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

    /// A fixed zone, so the tests do not depend on the machine's clock setting.
    private func calendar(_ zone: String) throws -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return cal
    }

    private func at(_ cal: Calendar, _ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) throws -> Date {
        try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
    }

    func testNextSweepIsTheNextTimeStrictlyAfterNow() throws {
        let cal = try calendar("Europe/London")
        // 21 Oct 2026 is a Wednesday. The times are unsorted on purpose.
        let times = [ScheduleTime("19:00")!, ScheduleTime("07:00")!, ScheduleTime("13:00")!]
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 21, 10), times: times, days: .all, calendar: cal),
                       try at(cal, 21, 13))
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 21, 19, 30), times: times, days: .all, calendar: cal),
                       try at(cal, 22, 7))
        // A sweep at exactly `now` is not the next one.
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 21, 13), times: times, days: .all, calendar: cal),
                       try at(cal, 21, 19))
    }

    func testWeekdaysOnSaturdayGoToMondayMorning() throws {
        let cal = try calendar("Europe/London")
        // 24 Oct 2026 is a Saturday.
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 24, 9), times: [ScheduleTime("07:00")!],
                                               days: .weekdays, calendar: cal),
                       try at(cal, 26, 7))
    }

    func testCustomDaysFollowTheWeekOrderAndSunday() throws {
        let cal = try calendar("Europe/London")
        let times = [ScheduleTime("07:00")!, ScheduleTime("13:00")!]
        // Wednesday 10:00 with Monday and Wednesday set: 13:00 the same day.
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 21, 10), times: times, days: .custom([.mon, .wed]),
                                               calendar: cal),
                       try at(cal, 21, 13))
        // Thursday: the next set day is Monday.
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 22, 10), times: times, days: .custom([.mon, .wed]),
                                               calendar: cal),
                       try at(cal, 26, 7))
        // Sunday is its own day, not Monday's neighbour in the week.
        XCTAssertEqual(ScheduleTimes.nextSweep(after: try at(cal, 24, 9), times: times, days: .custom([.sun]),
                                               calendar: cal),
                       try at(cal, 25, 7))
    }

    func testNextSweepAcrossTheDaylightSavingSwitch() throws {
        let cal = try calendar("America/New_York")
        // The US clocks go forward on 8 March 2026, so the night is 23 hours long.
        let before = try at(cal, 7, 7, month: 3)
        let next = try XCTUnwrap(ScheduleTimes.nextSweep(after: try at(cal, 7, 19, 30, month: 3),
                                                         times: [ScheduleTime("07:00")!], days: .all, calendar: cal))
        XCTAssertEqual(cal.component(.day, from: next), 8)
        XCTAssertEqual(cal.component(.hour, from: next), 7)
        XCTAssertEqual(next.timeIntervalSince(before), 23 * 3600)
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

    // MARK: Reconcile the job

    /// The job on disk is compared with what config.toml would write. No job, or no readable config, means nothing to do.
    func testJobNeedsReinstallOnlyWhenTheJobDiffers() throws {
        let dir = NSTemporaryDirectory() + "glidepath-reconcile-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let paths = Paths(home: dir, env: ["HOME": dir])
        try FileManager.default.createDirectory(atPath: paths.configDir, withIntermediateDirectories: true)
        try "schedule = [\"07:00\"]\n".write(toFile: paths.configFile, atomically: true, encoding: .utf8)
        XCTAssertFalse(ScheduleEditor.jobNeedsReinstall(paths), "no job installed")

        try FileManager.default.createDirectory(atPath: paths.agentsDir, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: URL(fileURLWithPath: paths.plistFile))
        XCTAssertTrue(ScheduleEditor.jobNeedsReinstall(paths), "job differs from the config")

        let config = try Config.load(paths)
        let wanted = try Launchd.data(binary: InitCommand.stableBinary(runningBinary: InitCommand.binaryPath()),
                                      schedule: config.schedule, days: config.days,
                                      path: InitCommand.jobPath(paths: paths), logFile: paths.logFile)
        try wanted.write(to: URL(fileURLWithPath: paths.plistFile))
        XCTAssertFalse(ScheduleEditor.jobNeedsReinstall(paths), "job matches the config")
    }
}
