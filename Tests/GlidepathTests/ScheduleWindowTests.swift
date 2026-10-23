import XCTest
@testable import Glidepath

final class ScheduleWindowTests: XCTestCase {
    private func t(_ text: String) -> ScheduleTime { ScheduleTime(text)! }

    func testTimesIncludeBothEnds() {
        XCTAssertEqual(ScheduleWindow.times(start: t("07:00"), end: t("19:00"), every: 240),
                       [t("07:00"), t("11:00"), t("15:00"), t("19:00")])
        XCTAssertEqual(ScheduleWindow.times(start: t("09:00"), end: t("10:00"), every: 30),
                       [t("09:00"), t("09:30"), t("10:00")])
    }

    func testTimesStopBeforeEndWhenTheIntervalDoesNotDivide() {
        XCTAssertEqual(ScheduleWindow.times(start: t("09:00"), end: t("10:00"), every: 40),
                       [t("09:00"), t("09:40")])
    }

    func testWindowCrossingMidnight() {
        XCTAssertEqual(ScheduleWindow.times(start: t("22:00"), end: t("02:00"), every: 120),
                       [t("00:00"), t("02:00"), t("22:00")])
        XCTAssertEqual(ScheduleWindow.times(start: t("23:00"), end: t("00:30"), every: 30),
                       [t("00:00"), t("00:30"), t("23:00"), t("23:30")])
    }

    func testEqualStartAndEndGiveOneTime() {
        XCTAssertEqual(ScheduleWindow.times(start: t("08:00"), end: t("08:00"), every: 60), [t("08:00")])
    }

    func testInferFindsTheWindowOfAnEvenlySpacedList() throws {
        let day = try XCTUnwrap(ScheduleWindow.infer(from: [t("19:00"), t("07:00"), t("11:00"), t("15:00")]))
        XCTAssertEqual(day.start, t("07:00"))
        XCTAssertEqual(day.end, t("19:00"))
        XCTAssertEqual(day.every, 240)
    }

    func testTimesClampTheIntervalToFifteenToTwoHundredForty() {
        XCTAssertEqual(ScheduleWindow.times(start: t("09:00"), end: t("10:00"), every: 5),
                       [t("09:00"), t("09:15"), t("09:30"), t("09:45"), t("10:00")])
        XCTAssertEqual(ScheduleWindow.times(start: t("09:00"), end: t("10:00"), every: 0),
                       [t("09:00"), t("09:15"), t("09:30"), t("09:45"), t("10:00")])
        XCTAssertEqual(ScheduleWindow.times(start: t("06:00"), end: t("18:00"), every: 1000),
                       [t("06:00"), t("10:00"), t("14:00"), t("18:00")])
    }

    func testInferRefusesSpacingOutsideFifteenToTwoHundredForty() {
        XCTAssertNil(ScheduleWindow.infer(from: [t("09:00"), t("09:10"), t("09:20")]), "10 minutes is too fine")
        XCTAssertNil(ScheduleWindow.infer(from: [t("00:00"), t("04:01")]), "241 minutes is too coarse")
        XCTAssertNil(ScheduleWindow.infer(from: [t("00:00"), t("06:00"), t("12:00"), t("18:00")]),
                     "360 minutes is too coarse")
        XCTAssertNotNil(ScheduleWindow.infer(from: [t("09:00"), t("09:15")]))
        XCTAssertNotNil(ScheduleWindow.infer(from: [t("00:00"), t("04:00")]))
    }

    func testInferHandlesAWindowCrossingMidnight() throws {
        let night = try XCTUnwrap(ScheduleWindow.infer(from: [t("22:00"), t("00:00"), t("02:00")]))
        XCTAssertEqual(night.start, t("22:00"))
        XCTAssertEqual(night.end, t("02:00"))
        XCTAssertEqual(night.every, 120)
        XCTAssertEqual(ScheduleWindow.times(start: night.start, end: night.end, every: night.every),
                       [t("00:00"), t("02:00"), t("22:00")])
    }

    func testInferRoundTripsWindows() throws {
        let windows: [(String, String, Int)] = [("06:00", "18:00", 60), ("20:00", "04:00", 240), ("00:15", "23:45", 90)]
        for (start, end, every) in windows {
            let times = ScheduleWindow.times(start: t(start), end: t(end), every: every)
            let back = try XCTUnwrap(ScheduleWindow.infer(from: times), "\(start)-\(end)")
            XCTAssertEqual(ScheduleWindow.times(start: back.start, end: back.end, every: back.every), times)
        }
    }

    func testInferRefusesUnevenOrTooFewTimes() {
        XCTAssertNil(ScheduleWindow.infer(from: [t("07:00"), t("08:00"), t("13:00")]))
        XCTAssertNil(ScheduleWindow.infer(from: [t("07:00")]))
        XCTAssertNil(ScheduleWindow.infer(from: []))
        XCTAssertNil(ScheduleWindow.infer(from: [t("07:00"), t("07:00"), t("12:00")]), "a repeated time is not a spacing")
    }
}
