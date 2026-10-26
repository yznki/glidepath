import XCTest
@testable import Glidepath

final class MenuBarTests: XCTestCase {
    @MainActor
    func testPauseOffersAnHourTomorrowAtNineAndUntilResumed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15, minute: 10))!
        let choices = MenuActions.pauseChoices(now: now, calendar: calendar)
        XCTAssertEqual(choices.map(\.title).first, Copy.pauseOneHour)
        XCTAssertEqual(choices[0].until, now.addingTimeInterval(3600))
        XCTAssertEqual(choices[1].until, calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9)))
        XCTAssertTrue(choices[1].title.hasPrefix("Until tomorrow "))
        XCTAssertEqual(choices[2].title, Copy.pauseUntilResume)
        XCTAssertNil(choices[2].until)
    }

    func testTheStatusControlMatchesItsWord() {
        let cases: [(GlideState, MenuAction)] = [
            (.quiet(next: nil), .checkNow),
            (.checking(CheckProgress()), .stop),
            (.needs(count: 2), .openWindow),
            (.paused(until: nil), .resume),
            (.problem(reason: .signedOut, fix: .signIn), .fix(.signIn)),
            (.holdingBack(reason: .quietHours, resumesAt: nil), .adjust),
        ]
        for (state, action) in cases {
            XCTAssertEqual(MenuAction.control(for: state), action, Copy.statusButton(state))
        }
        XCTAssertFalse(MenuAction.checkNow.closesPopover, "Check now keeps the popover open to show it running")
        XCTAssertTrue(MenuAction.openWindow.closesPopover)
    }

    @MainActor
    func testTheIconHidesTheCountWhenPausedOrBroken() {
        XCTAssertTrue(MenuBar.hidesCount(.paused(until: nil)))
        XCTAssertTrue(MenuBar.hidesCount(.problem(reason: .notSetUp, fix: .setUp)))
        XCTAssertFalse(MenuBar.hidesCount(.needs(count: 3)))
        XCTAssertFalse(MenuBar.hidesCount(.checking(CheckProgress())), "the count stays while a check runs")
    }
}
