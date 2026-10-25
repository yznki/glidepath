import XCTest
@testable import Glidepath

/// What History and Now read from a run: its rows, which run a PR's review is opened from, and the day headings.
final class HistoryTests: XCTestCase {
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
    }

    func testUnfinishedRunDropsVerdictlessRow() {
        let rows = sweepsFrom([run("r1", finished: false, [pr(1, verdict: .approve), pr(2)])]).first?.rows ?? []
        XCTAssertEqual(rows.map(\.number), [1])
    }

    func testCarriedRowIsNotListed() {
        let rows = sweepsFrom([run("r1", finished: true, [pr(1, carried: true), pr(2, verdict: .changes)])]).first?.rows ?? []
        XCTAssertEqual(rows.map(\.number), [2])
    }

    func testRowLookupFindsTheNewestRunWithThePR() {
        let list = sweepsFrom([run("new", at: 3600, finished: true, [pr(1, carried: true), pr(2, verdict: .changes)]),
                               run("old", finished: true, [pr(1, verdict: .approve), pr(9, verdict: .changes)])])
        XCTAssertEqual(ReviewsModel.row(runID: nil, stripID: "acme/api#9", in: list)?.runId, "old")
        XCTAssertEqual(ReviewsModel.row(runID: nil, stripID: "acme/api#1", in: list)?.runId, "old")
        XCTAssertNil(ReviewsModel.row(runID: nil, stripID: "acme/api#77", in: list))
    }

    func testRowLookupPrefersTheCardsOwnRun() {
        let list = sweepsFrom([run("new", at: 3600, finished: true, [pr(1, verdict: .changes)]),
                               run("old", finished: true, [pr(1, verdict: .approve)])])
        XCTAssertEqual(ReviewsModel.row(runID: "old", stripID: "acme/api#1", in: list)?.runId, "old")
    }

    func testNewestKeepsTheNewestRunsFirst() {
        let runs = ReviewsModel.newest([run("old", finished: true, []), run("new", at: 60, finished: true, [])])
        XCTAssertEqual(runs.map(\.id), ["new", "old"])
    }

    func testDayTitleNamesTodayAndYesterday() {
        XCTAssertEqual(ReviewsModel.dayTitle(Date()), "Today")
        XCTAssertEqual(ReviewsModel.dayTitle(Date().addingTimeInterval(-86_400)), "Yesterday")
    }
}
