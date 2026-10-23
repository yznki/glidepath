import XCTest
@testable import Glidepath

final class ScheduleDialTests: XCTestCase {
    private func t(_ text: String) -> ScheduleTime { ScheduleTime(text)! }

    func testPresetsYieldTheSweepsTheyDescribe() {
        let office = DialPreset.all[0].window.times
        XCTAssertEqual(office.count, 19)
        XCTAssertEqual(office.first, t("09:00"))
        XCTAssertEqual(office.last, t("18:00"))
        XCTAssertEqual(DialPreset.all[1].window.times.count, 24, "whole day, hourly, no repeated midnight")
        XCTAssertEqual(DialPreset.all[2].window.times.count, 11)
        XCTAssertTrue(DialPreset.all[2].window.times.contains(t("03:30")), "night shift stops at the last 45-minute step")
    }

    func testWholeDayRoundTripsThroughTheConfigTimes() {
        let whole = DialWindow(start: 0, span: 1440, every: 60)
        let back = DialWindow.from(times: whole.times)
        XCTAssertEqual(back, whole)
    }

    func testWholeDaySnapsIntervalToADivisorOfTheDay() {
        XCTAssertEqual(DialWindow(start: 0, span: 1440, every: 50).every, 48, "nearest divisor of 1440")
        XCTAssertEqual(DialWindow(start: 0, span: 1440, every: 100).every, 96)
        XCTAssertEqual(DialWindow(start: 0, span: 1440, every: 500).every, 240, "clamped first")
        XCTAssertEqual(DialWindow(start: 0, span: 540, every: 50).every, 50, "partial windows keep any interval")
    }

    func testFromTimesRecoversWindowsAcrossMidnight() {
        let night = DialPreset.all[2].window
        XCTAssertEqual(DialWindow.from(times: night.times)?.start, 20 * 60)
        XCTAssertEqual(DialWindow.from(times: night.times)?.every, 45)
        XCTAssertNil(DialWindow.from(times: [t("08:00"), t("08:20"), t("12:00")]))
    }

    func testMovingEndOntoStartIsTheWholeDay() {
        let window = DialWindow(start: 540, span: 540, every: 30)
        XCTAssertEqual(window.movedEnd(to: 540).span, 1440)
        XCTAssertEqual(window.movedStart(to: 0).end, 1080, "end stays put when the start moves")
    }

    func testMinuteFromPointSnapsAndPointsMidnightUp() {
        XCTAssertEqual(DialWindow.minute(dx: 0, dy: -100), 0)
        XCTAssertEqual(DialWindow.minute(dx: 100, dy: 0), 360)
        XCTAssertEqual(DialWindow.minute(dx: 1, dy: -100), 0)
    }

    func testDaysNormaliseToTheSettings() {
        XCTAssertEqual(DialDays.schedule(Set(Weekday.allCases.prefix(5))), .weekdays)
        XCTAssertEqual(DialDays.schedule(Set(Weekday.allCases)), .all)
        XCTAssertEqual(DialDays.schedule([.sat]), .custom([.sat]))
    }

    func testBudgetOnlyCountsWhenSet() {
        XCTAssertEqual(DialStats.tokensPerMonth(perWeek: 10, perSweep: 9_000), 387_000)
        XCTAssertTrue(DialStats.overBudget(tokens: 500, budget: 400))
        XCTAssertFalse(DialStats.overBudget(tokens: 500, budget: 0))
        XCTAssertEqual(DialFormat.compact(1_200_000), "1.2M")
        XCTAssertEqual(DialFormat.compact(48_000), "48k")
    }

    func testUnmeasuredSweepsFallBackToPerPRGuessTimesMaxPRs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runs = (0..<2).map { i in
            RunState(id: "r\(i)", started: now.addingTimeInterval(-3600), finished: now, repos: [], tokens: 900_000,
                     error: nil, kind: nil)
        }
        XCTAssertNil(DialStats.sweepTokens(runs, now: now), "fewer than three finished sweeps is not history")
        let perSweep = DialStats.perSweepGuess(maxPRs: 5)
        XCTAssertEqual(perSweep, 1_700_000)
        XCTAssertEqual(DialStats.tokensPerMonth(perWeek: 10, perSweep: perSweep), 73_100_000)
    }

    func testUpcomingSkipsOffDays() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2026-10-23 is a Friday.
        let friday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 10)))
        let dates = DialUpcoming.next(3, after: friday, times: [t("09:00")], days: .weekdays, calendar: cal)
        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(cal.component(.weekday, from: dates[0]), 2, "Monday after a Friday")
    }

    func testUntilTomorrowIsTheFirstTimeOfTheNextSweepDay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let friday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15)))
        let until = try XCTUnwrap(DialPause.tomorrow(now: friday, times: [t("18:00"), t("09:30")], days: .weekdays, calendar: cal))
        XCTAssertEqual(cal.component(.day, from: until), 26, "Monday, skipping the weekend")
        XCTAssertEqual(cal.component(.hour, from: until), 9)
        XCTAssertEqual(cal.component(.minute, from: until), 30)
    }
}
