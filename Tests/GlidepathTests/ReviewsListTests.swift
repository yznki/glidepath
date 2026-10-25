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

    private func run(_ id: String, at offset: TimeInterval = 0, finished: Bool, _ prs: [PRState]) -> RunState {
        let started = Date(timeIntervalSince1970: 1_000 + offset)
        return RunState(id: id, started: started, finished: finished ? started.addingTimeInterval(60) : nil,
                        repos: [RepoState(slug: "acme/api", prs: prs, error: nil)], tokens: 0, error: nil)
    }

    private func pr(_ n: Int, verdict: Verdict? = nil, carried: Bool = false) -> PRState {
        var state = PRState(n: n, author: "sam", title: "PR \(n)", stage: .review, active: false, verdict: verdict,
                            reason: nil, tokens: 0)
        if carried { state.carriedFrom = Date(timeIntervalSince1970: 500) }
        return state
    }

    private func sweepsFrom(_ runs: [RunState]) -> [ReviewSweep] {
        ReviewsModel.sweeps(from: runs) { _, _, _ in nil }
    }

    func testFinishedRunKeepsVerdictlessRowAsNoResult() {
        let rows = sweepsFrom([run("r1", finished: true, [pr(1, verdict: .approve), pr(2)])]).first?.rows ?? []
        XCTAssertEqual(rows.map(\.number), [1, 2])
        XCTAssertNil(rows[1].verdict)
        XCTAssertTrue(ReviewFilter.all.includes(rows[1]))
        for filter in [ReviewFilter.approved, .changes, .skipped, .waiting] {
            XCTAssertFalse(filter.includes(rows[1]), "\(filter) counts a No result row")
        }
    }

    func testUnfinishedRunDropsVerdictlessRow() {
        let rows = sweepsFrom([run("r1", finished: false, [pr(1, verdict: .approve), pr(2)])]).first?.rows ?? []
        XCTAssertEqual(rows.map(\.number), [1])
    }

    func testCarriedRowIsNotListed() {
        let rows = sweepsFrom([run("r1", finished: true, [pr(1, carried: true), pr(2, verdict: .changes)])]).first?.rows ?? []
        XCTAssertEqual(rows.map(\.number), [2])
    }

    func testCurrentSweepIsTheNewestWithRows() {
        let list = sweepsFrom([run("new", at: 3600, finished: true, [pr(2, carried: true)]),
                               run("old", finished: true, [pr(1, verdict: .approve)])])
        XCTAssertEqual(ReviewsModel.current(in: list)?.id, "old")
        XCTAssertNil(ReviewsModel.current(in: []))
    }

    func testRowLookupFindsTheNewestSweepWithThePR() {
        let list = sweepsFrom([run("new", at: 3600, finished: true, [pr(1, carried: true), pr(2, verdict: .changes)]),
                               run("old", finished: true, [pr(1, verdict: .approve), pr(9, verdict: .changes)])])
        XCTAssertEqual(ReviewsModel.row(stripID: "acme/api#9", in: list)?.runId, "old")
        XCTAssertEqual(ReviewsModel.row(stripID: "acme/api#1", in: list)?.runId, "old")
        XCTAssertNil(ReviewsModel.row(stripID: "acme/api#77", in: list))
    }
}
