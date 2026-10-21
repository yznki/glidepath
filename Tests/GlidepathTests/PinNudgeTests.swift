import XCTest
@testable import Glidepath

final class PinNudgeTests: XCTestCase {
    func t(_ text: String) -> ScheduleTime { ScheduleTime(text)! }

    func testStepsAreFifteenMinutesAndAnHour() {
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: 15, among: [t("07:00")])?.text, "07:15")
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: -15, among: [t("07:00")])?.text, "06:45")
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: 60, among: [t("07:00")])?.text, "08:00")
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: -60, among: [t("07:00")])?.text, "06:00")
    }

    func testClampsToTheDay() {
        XCTAssertNil(PinNudge.target(from: t("00:00"), by: -15, among: [t("00:00")]))
        XCTAssertNil(PinNudge.target(from: t("23:45"), by: 15, among: [t("23:45")]))
        XCTAssertNil(PinNudge.target(from: t("23:45"), by: 60, among: [t("23:45")]))
        XCTAssertEqual(PinNudge.target(from: t("23:30"), by: 60, among: [t("23:30")])?.text, "23:45")
        XCTAssertEqual(PinNudge.target(from: t("00:30"), by: -60, among: [t("00:30")])?.text, "00:00")
    }

    func testLandingOnAListedTimeSkipsPast() {
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: 15, among: [t("07:00"), t("07:15")])?.text, "07:30")
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: 60, among: [t("07:00"), t("08:00")])?.text, "08:15")
        XCTAssertEqual(PinNudge.target(from: t("07:00"), by: -15, among: [t("06:45"), t("07:00")])?.text, "06:30")
    }

    func testNoFreeStepInRangeMeansNoMove() {
        let packed = ["23:00", "23:15", "23:30", "23:45"].map(t)
        XCTAssertNil(PinNudge.target(from: t("23:00"), by: 15, among: packed))
    }

    func testMinuteOfDayRoundTrips() {
        XCTAssertEqual(ScheduleTime(minuteOfDay: 13 * 60 + 5)?.text, "13:05")
        XCTAssertNil(ScheduleTime(minuteOfDay: 1440))
    }

    func testSetScheduleKeepsOneTimeAndSorts() throws {
        let config = Config(schedule: [t("13:00")], limits: Limits(), repos: [])
        let out = try ScheduleEditor.setSchedule(config, [t("19:00"), t("07:00")])
        XCTAssertEqual(out.schedule.map(\.text), ["07:00", "19:00"])
        XCTAssertThrowsError(try ScheduleEditor.setSchedule(config, []))
    }
}
