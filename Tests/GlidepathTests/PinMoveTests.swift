import XCTest
@testable import Glidepath

/// The schedule's save race: what is left to save once a move has been written.
final class PinMoveTests: XCTestCase {
    func t(_ text: String) -> ScheduleTime { ScheduleTime(text)! }

    func testNothingLeftWhenTheKeysStoppedAtTheSavedTime() {
        let saved = PinMove(from: t("07:00"), to: t("07:30"))
        XCTAssertNil(PinMove.settle(saved, saved: saved))
    }

    func testMovedAgainDuringTheSaveRebasesOnTheSavedTime() {
        let saved = PinMove(from: t("07:00"), to: t("07:15"))
        let moved = PinMove(from: t("07:00"), to: t("07:45"))
        // The pin is on disk at 07:15 now, so the rest of the move starts there.
        XCTAssertEqual(PinMove.settle(moved, saved: saved), PinMove(from: t("07:15"), to: t("07:45")))
    }

    func testNoDraftStaysNoDraft() {
        XCTAssertNil(PinMove.settle(nil, saved: PinMove(from: t("07:00"), to: t("07:15"))))
    }
}
