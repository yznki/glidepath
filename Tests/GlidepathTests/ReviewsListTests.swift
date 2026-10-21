import XCTest
@testable import Glidepath

/// The Reviews list's All filter, the fold of skipped PRs into a sweep's summary line, and the summary's counts.
final class ReviewsListTests: XCTestCase {
    private func row(_ n: Int, _ verdict: Verdict?, _ reason: String? = nil, size: Bool = false, draft: Bool = false) -> ReviewRow {
        ReviewRow(runId: "run-1", repo: "acme/api", number: n, author: "sam", title: "PR \(n)", reason: reason,
                  verdict: verdict, draft: draft, skipReason: size ? "size" : nil, changedLines: nil, head: nil,
                  flagged: false, tokens: 0, duration: nil, postedAt: nil)
    }

    private let tooLarge = "too large (4000 changed lines)"

    func testAllShowsEverythingButSkipsExceptTooLarge() {
        XCTAssertTrue(ReviewFilter.all.includes(row(1, .changes)))
        XCTAssertTrue(ReviewFilter.all.includes(row(2, .approve)))
        XCTAssertTrue(ReviewFilter.all.includes(row(3, nil, draft: true)))
        XCTAssertFalse(ReviewFilter.all.includes(row(4, .skipped, "your own PR")))
        XCTAssertTrue(ReviewFilter.all.includes(row(5, .skipped, tooLarge, size: true)))
    }

    func testSkippedSegmentStillListsEverySkip() {
        XCTAssertTrue(ReviewFilter.skipped.includes(row(4, .skipped, "your own PR")))
        XCTAssertTrue(ReviewFilter.skipped.includes(row(5, .skipped, tooLarge, size: true)))
        XCTAssertFalse(ReviewFilter.skipped.includes(row(1, .changes)))
    }

    func testAllFoldsSkipsExceptTooLarge() {
        let rows = [row(1, .changes), row(2, .skipped, "your own PR"), row(3, .skipped, tooLarge, size: true),
                    row(4, .skipped, "bot author")]
        let all = ReviewSweep.split(rows, filter: .all)
        XCTAssertEqual(all.shown.map(\.number), [1, 3])
        XCTAssertEqual(all.folded.map(\.number), [2, 4])
        let skipped = ReviewSweep.split(rows, filter: .skipped)
        XCTAssertEqual(skipped.shown.map(\.number), [2, 3, 4])
        XCTAssertTrue(skipped.folded.isEmpty, "the Skipped segment folds nothing")
    }

    func testSummaryCountsFoldedSkipsByReasonAndLeavesOutTooLarge() {
        let rows = [row(6, .changes),
                    row(1, .skipped, "your own PR"), row(2, .skipped, "your own PR"),
                    row(3, .skipped, "already reviewed at this head"), row(4, .skipped, "bot author"),
                    row(5, .skipped, tooLarge, size: true)]
        let sweep = ReviewSweep(id: "run-1", started: Date(), isReview: false, duration: nil, rows: rows)
            .filtered(by: .all, expanded: false)
        XCTAssertEqual(sweep.entries.count, 3, "two rows, then the summary line")
        XCTAssertEqual(sweep.entries.last.map(\.id), ReviewEntry.skippedID("run-1"))
        guard case .skipped(_, let text, let expanded)? = sweep.entries.last else { return XCTFail("no summary line") }
        XCTAssertEqual(text, "4 skipped: 2 yours, 1 already reviewed, 1 bots")
        XCTAssertFalse(expanded)
    }

    func testExpandedSummaryListsItsSkipsAfterItself() {
        let rows = [row(1, .skipped, "your own PR"), row(2, .skipped, "bot author")]
        let sweep = ReviewSweep(id: "run-1", started: Date(), isReview: false, duration: nil, rows: rows)
            .filtered(by: .all, expanded: true)
        XCTAssertEqual(sweep.entries.map(\.id), [ReviewEntry.skippedID("run-1"), rows[0].id, rows[1].id])
    }

    func testSweepWithOnlyTooLargeSkipsHasNoSummary() {
        let rows = [row(5, .skipped, tooLarge, size: true)]
        let sweep = ReviewSweep(id: "run-1", started: Date(), isReview: false, duration: nil, rows: rows)
            .filtered(by: .all, expanded: false)
        XCTAssertEqual(sweep.entries.map(\.id), [rows[0].id])
    }
}
