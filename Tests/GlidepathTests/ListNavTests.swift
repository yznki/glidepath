import XCTest
@testable import Glidepath

final class ListNavTests: XCTestCase {
    func testArrowsStepAndClamp() {
        XCTAssertEqual(ListNav.move(.down, from: 0, count: 3), 1)
        XCTAssertEqual(ListNav.move(.down, from: 2, count: 3), 2)
        XCTAssertEqual(ListNav.move(.up, from: 0, count: 3), 0)
        XCTAssertEqual(ListNav.move(.up, from: 2, count: 3), 1)
    }

    func testNoSelectionLandsOnFirstAndEmptyListHasNoSelection() {
        XCTAssertEqual(ListNav.move(.down, from: nil, count: 3), 0)
        XCTAssertEqual(ListNav.move(.up, from: nil, count: 3), 0)
        XCTAssertNil(ListNav.move(.down, from: 0, count: 0))
    }

    func testFirstLastAndPages() {
        XCTAssertEqual(ListNav.move(.last, from: 1, count: 20), 19)
        XCTAssertEqual(ListNav.move(.first, from: 15, count: 20), 0)
        XCTAssertEqual(ListNav.move(.pageDown, from: 2, count: 20), 10)
        XCTAssertEqual(ListNav.move(.pageDown, from: 15, count: 20), 19)
        XCTAssertEqual(ListNav.move(.pageUp, from: 10, count: 20), 2)
        XCTAssertEqual(ListNav.move(.pageUp, from: 3, count: 20), 0)
    }

    func testGroupJumpsGoToGroupStarts() {
        let starts = [0, 4, 9]
        XCTAssertEqual(ListNav.move(.groupNext, from: 0, count: 12, groupStarts: starts), 4)
        XCTAssertEqual(ListNav.move(.groupNext, from: 6, count: 12, groupStarts: starts), 9)
        XCTAssertEqual(ListNav.move(.groupNext, from: 9, count: 12, groupStarts: starts), 9, "no later group: stay")
        // Inside a group, previous goes to its start first; from a start, to the group before.
        XCTAssertEqual(ListNav.move(.groupPrevious, from: 6, count: 12, groupStarts: starts), 4)
        XCTAssertEqual(ListNav.move(.groupPrevious, from: 4, count: 12, groupStarts: starts), 0)
        XCTAssertEqual(ListNav.move(.groupPrevious, from: 0, count: 12, groupStarts: starts), 0)
    }

    func testKeyMapping() {
        XCTAssertEqual(ListNav.move(.up, []), .up)
        XCTAssertEqual(ListNav.move(.down, [.command]), .last)
        XCTAssertEqual(ListNav.move(.up, [.command]), .first)
        XCTAssertEqual(ListNav.move(.up, [.option]), .groupPrevious)
        XCTAssertEqual(ListNav.move(.down, [.option]), .groupNext)
        XCTAssertEqual(ListNav.move(.home, []), .first)
        XCTAssertEqual(ListNav.move(.pageDown, []), .pageDown)
        XCTAssertNil(ListNav.move(.up, [.shift]), "shift arrows are left to the text field")
    }

    func testTypeToSelectMatchesTitlePrefix() {
        let titles = ["Fix login", "Add tests", "Bump deps", "Add docs"]
        XCTAssertEqual(ListNav.typeSelect("bu", titles: titles, from: nil), 2)
        XCTAssertEqual(ListNav.typeSelect("a", titles: titles, from: nil), 1)
        // A repeated letter cycles to the next match.
        XCTAssertEqual(ListNav.typeSelect("a", titles: titles, from: 1), 3)
        XCTAssertNil(ListNav.typeSelect("zz", titles: titles, from: nil))
        XCTAssertNil(ListNav.typeSelect("", titles: titles, from: nil))
    }
}
