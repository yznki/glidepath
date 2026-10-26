import XCTest
@testable import Glidepath

final class RunDigestTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func pr(_ n: Int, _ verdict: Verdict?, reason: String? = nil, active: Bool = false,
                    carried: Bool = false, skipReason: String? = nil) -> PRState {
        PRState(n: n, author: "eleyy", title: "PR \(n)", stage: .post, active: active, verdict: verdict,
                reason: reason, tokens: 0, carriedFrom: carried ? t0.addingTimeInterval(-3600) : nil,
                skipReason: skipReason)
    }

    private func run(kind: String?, target: String?, repos: [(String, [PRState])], finished: Bool = true) -> RunState {
        var run = RunState.new(id: "r", now: t0, kind: kind, target: target)
        run.repos = repos.map { RepoState(slug: $0.0, prs: $0.1, error: nil) }
        if finished { run.finished = t0.addingTimeInterval(600) }
        return run
    }

    private let alreadyReviewed = "already reviewed at this head"

    func testTitleForSelfReviewAndTidyingRuns() {
        XCTAssertEqual(RunDigest.title(for: run(kind: "self-review", target: "prs:lumen/api#7", repos: [])), "Self-review of #7")
        var selfRound = RunState.new(id: "r", now: t0, kind: "tend", target: "pr:lumen/api#7")
        selfRound.tendAction = "self-review"
        XCTAssertEqual(RunDigest.title(for: selfRound), "Self-review of #7")
        var tidy = RunState.new(id: "r", now: t0, kind: "tend", target: "repo:lumen/api")
        tidy.tendAction = "consolidated"
        XCTAssertEqual(RunDigest.title(for: tidy), "Lessons tidied for lumen/api")
    }

    func testOnlyTendRoundsCountAsRounds() {
        func tend(_ action: String?) -> RunState {
            var r = RunState.new(id: "r", now: t0, kind: "tend", target: "pr:lumen/api#7")
            r.tendAction = action
            return r
        }
        XCTAssertTrue(RunDigest.isRound(tend("fixed")))
        XCTAssertTrue(RunDigest.isRound(tend("answered")))
        XCTAssertTrue(RunDigest.isRound(tend("merged")))
        XCTAssertFalse(RunDigest.isRound(tend("self-review")))
        XCTAssertFalse(RunDigest.isRound(tend("landed")))
        XCTAssertFalse(RunDigest.isRound(tend("broke")))
        XCTAssertFalse(RunDigest.isRound(tend("consolidated")))
        XCTAssertFalse(RunDigest.isRound(run(kind: "review", target: "prs:lumen/api#7", repos: [])))
    }

    func testTitleForEachTargetForm() {
        XCTAssertEqual(RunDigest.title(for: run(kind: nil, target: nil, repos: [])), "Sweep")
        XCTAssertEqual(RunDigest.title(for: run(kind: "review", target: nil, repos: [])), "Review")
        XCTAssertEqual(RunDigest.title(for: run(kind: "review", target: "author:eleyy", repos: [])), "eleyy's PRs")
        XCTAssertEqual(RunDigest.title(for: run(kind: "review", target: "prs:lumen/api#1212", repos: [])),
                       "lumen/api #1212")
        XCTAssertEqual(RunDigest.title(for: run(kind: "review", target: "prs:lumen/api#1212,lumen/web#7", repos: [])),
                       "2 PRs")
    }

    func testCarriedRowsAreLeftOut() {
        let r = run(kind: "review", target: "author:eleyy", repos: [
            ("lumen/api", [pr(1, .approve), pr(2, .approve, carried: true), pr(3, .skipped, reason: "draft")]),
        ])
        let digest = RunDigest(run: r, running: false)
        XCTAssertEqual(digest.ownRows.map(\.pr.n), [1, 3])
        XCTAssertEqual(digest.reviewed.map(\.pr.n), [1])
        XCTAssertEqual(digest.lead, "Reviewed 1 of 2.")
    }

    func testEleyyCaseReadsAsOneSentence() {
        var rows = [pr(1, .changes), pr(2, .approve), pr(3, .changes), pr(4, .approve)]
        rows += (10..<31).map { pr($0, .skipped, reason: alreadyReviewed) }
        let digest = RunDigest(run: run(kind: "review", target: "author:eleyy", repos: [("lumen/web", rows)]),
                               running: false)
        XCTAssertEqual(digest.lead, "Reviewed 4 of 25.")
        XCTAssertEqual(digest.rest, "You'd already reviewed the other 21, and nothing changed since.")
    }

    func testAllAlreadyReviewedWithNothingReviewed() {
        let rows = (10..<13).map { pr($0, .skipped, reason: alreadyReviewed) }
        let digest = RunDigest(run: run(kind: "review", target: "author:eleyy", repos: [("lumen/web", rows)]),
                               running: false)
        XCTAssertEqual(digest.lead, "Nothing reviewed.")
        XCTAssertEqual(digest.rest, "You'd already reviewed all 3, and nothing changed since.")
    }

    func testOneAlreadyReviewedReadsAsTheOtherOne() {
        let rows = [pr(1, .approve), pr(2, .skipped, reason: alreadyReviewed)]
        let digest = RunDigest(run: run(kind: "review", target: "author:eleyy", repos: [("lumen/web", rows)]),
                               running: false)
        XCTAssertEqual(digest.rest, "You'd already reviewed the other one, and nothing changed since.")
    }

    func testMixedSweepGroupsSkips() {
        var rows = (1...5).map { pr($0, .approve) }
        rows += [pr(6, nil), pr(7, nil)]
        rows += (10..<21).map { pr($0, .skipped, reason: "your own PR") }
        rows += (30..<37).map { pr($0, .skipped, reason: "bot author") }
        rows += (40..<42).map { pr($0, .skipped, reason: alreadyReviewed) }
        rows.append(pr(50, .skipped, reason: "draft"))
        rows.append(pr(51, .skipped, reason: "too large (900 changed lines)"))
        let digest = RunDigest(run: run(kind: nil, target: nil, repos: [("lumen/api", rows)]), running: false)
        XCTAssertEqual(digest.title, "Sweep")
        XCTAssertEqual(digest.lead, "Reviewed 5, 2 stopped.")
        XCTAssertEqual(digest.rest,
                       "22 skipped: 11 yours, 7 bots, 2 already reviewed, 1 draft, 1 too large.")
    }

    func testStoppedOnlyLeadHasNoReviewedCount() {
        let rows = [pr(1, nil), pr(2, nil)]
        let digest = RunDigest(run: run(kind: nil, target: nil, repos: [("lumen/api", rows)]), running: false)
        XCTAssertEqual(digest.lead, "2 stopped.")
    }

    func testOlderSizeSkipCountsAsTooLarge() {
        let rows = [pr(1, .approve), pr(2, .skipped, reason: "something else", skipReason: "size")]
        let digest = RunDigest(run: run(kind: nil, target: nil, repos: [("lumen/api", rows)]), running: false)
        XCTAssertEqual(digest.rest, "1 skipped: 1 too large.")
    }

    func testRunningLeadCountsOwnRowsOnly() {
        var rows = [pr(1, .approve), pr(2, nil, active: true), pr(3, nil, active: true), pr(4, nil)]
        rows += (10..<31).map { pr($0, .skipped, reason: alreadyReviewed) }
        let digest = RunDigest(run: run(kind: "review", target: "author:eleyy", repos: [("lumen/web", rows)],
                                        finished: false), running: true)
        XCTAssertEqual(digest.lead, "1 of 4 reviewed.")
        XCTAssertEqual(digest.inFlight.map(\.pr.n), [2, 3])
        XCTAssertEqual(digest.stopped, [])
        XCTAssertEqual(digest.done, 1)
        XCTAssertEqual(digest.toReview, 4)
    }

    func testDeadRunShowsStoppedRowsNotInFlight() {
        let rows = [pr(1, .approve), pr(2, nil, active: true), pr(3, nil, active: true)]
        let digest = RunDigest(run: run(kind: nil, target: nil, repos: [("lumen/api", rows)], finished: false),
                               running: false)
        XCTAssertEqual(digest.inFlight, [])
        XCTAssertEqual(digest.stopped.map(\.pr.n), [2, 3])
        XCTAssertEqual(digest.lead, "Reviewed 1, 2 stopped.")
    }

    func testRunErrorReadsAsFailed() {
        var r = run(kind: nil, target: nil, repos: [("lumen/api", [pr(1, .approve)])])
        r.error = "claude exited 1: boom"
        let digest = RunDigest(run: r, running: false)
        XCTAssertEqual(digest.failed, "claude exited 1: boom")
        XCTAssertEqual(digest.lead, "Failed.")
        XCTAssertEqual(digest.rest, "claude exited 1: boom")
    }

    func testRepoErrorReadsAsFailed() {
        var r = run(kind: nil, target: nil, repos: [("lumen/api", [pr(1, .approve)])])
        r.repos[0].error = "gh timed out"
        let digest = RunDigest(run: r, running: false)
        XCTAssertEqual(digest.failed, "gh timed out")
        XCTAssertEqual(digest.lead, "Failed.")
    }

    func testNothingReviewedWhenNothingStoppedOrDone() {
        let digest = RunDigest(run: run(kind: nil, target: nil, repos: [("lumen/api", [pr(1, .skipped, reason: "draft")])]),
                               running: false)
        XCTAssertEqual(digest.lead, "Nothing reviewed.")
        XCTAssertEqual(digest.rest, "1 skipped: 1 draft.")
    }
}
