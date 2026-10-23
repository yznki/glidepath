import XCTest
@testable import Glidepath

final class StackCapTests: XCTestCase {
    func strip(_ n: Int, active: Bool = false, verdict: Verdict? = nil) -> Strip {
        Strip(repo: "acme/api", number: n, author: "ines", title: "T\(n)", reason: nil, stage: 1,
              active: active, verdict: verdict, tokens: 0)
    }

    /// 45 PRs as in the real case: 10 running, 35 skipped.
    func testFortyFiveStripsCapAtSixWithThirtyNineMore() {
        let all = (1...10).map { strip($0, active: true) } + (11...45).map { strip($0, verdict: .skipped) }
        let ordered = StackGeometry.ordered(all, running: true, filter: nil)
        let shown = StackGeometry.cap(ordered)
        XCTAssertEqual(shown.cards.count, StackGeometry.maxCards)
        XCTAssertEqual(shown.more, 39)
        XCTAssertTrue(shown.cards.allSatisfy { $0.active }, "running cards come first")
        XCTAssertEqual(ordered.last?.verdict, .skipped, "skipped cards sort last")
    }

    /// A re-rank can move the open card past the cap; it still shows, and the card it displaces is counted in "more".
    func testOpenCardPastTheCapStillShows() {
        let all = (1...8).map { strip($0) }
        let open = all[7].id
        let shown = StackGeometry.cap(all, open: open)
        XCTAssertTrue(shown.cards.contains { $0.id == open })
        XCTAssertEqual(shown.cards.count, StackGeometry.maxCards)
        XCTAssertEqual(shown.more, 2)
    }
}
