import XCTest
@testable import Glidepath

final class NeedsYouTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func run() throws -> RunState {
        var run = RunState.new(id: "r1", now: t0)
        try run.setPR(repo: "acme/web", n: 10, stage: .post, author: "ines", title: "Held review", verdict: .changes, reason: nil)
        try run.setPR(repo: "acme/web", n: 11, stage: nil, author: "tom", title: "Huge", verdict: .skipped, reason: "too large")
        try run.setPR(repo: "acme/web", n: 12, stage: .post, author: "ana", title: "Posted", verdict: .approve, reason: nil)
        run.repos[0].prs[0].draft = true
        run.repos[0].prs[1].skipReason = "size"
        run.repos[0].prs[1].changedLines = 12_480
        // A size skip carried from an earlier run was offered by that run: not again.
        run.repos[0].prs.append(PRState(n: 13, author: "lee", title: "Old huge", stage: .gather, active: false,
                                        verdict: .skipped, reason: "too large", tokens: 0, carriedFrom: t0, skipReason: "size"))
        run.finish(at: t0.addingTimeInterval(60), error: nil)
        return run
    }

    /// Every kind 1.10 has, built the way tend and the store build them.
    private func snapshot() throws -> Snapshot {
        var snap = Snapshot(run: try run())
        snap.repoCount = 1
        snap.config = try Config.parse("""
        schedule = ["09:00"]
        [[repo]]
        slug = "acme/web"
        clone = "/tmp/web"
        posting = "draft"
        """, home: "/tmp")
        var held = TendPR(slug: "acme/api", n: 20)
        held.held = TendHeld(commit: "abc", summary: "Fixed the flaky date test", at: t0.addingTimeInterval(-500))
        var stuck = TendPR(slug: "acme/api", n: 21)
        stuck.stuck = "Tried twice; the error is in generated code"
        let reply = YourCall(id: "c1", kind: "thread", author: "gadi", quote: "Why not cache this?", draft: "Because…",
                             at: t0.addingTimeInterval(-300))
        let ask = YourCall(id: "c2", kind: "review", author: "noa", quote: "Is this safe?", draft: nil, at: t0.addingTimeInterval(-200))
        var calls = TendPR(slug: "acme/api", n: 22)
        calls.calls = [reply, ask]
        let split = SplitPlan(slug: "acme/api", n: 23, head: "h", branch: "b", base: "main",
                              parts: [SplitPart(title: "a", files: ["x"]), SplitPart(title: "b", files: ["y"])],
                              status: "proposed", at: t0.addingTimeInterval(-100))
        let broke = TendLanded(slug: "acme/api", n: 24, title: "Merged one", sha: "s", parent: "p", at: t0.addingTimeInterval(-900),
                               status: "broke", failing: ["lint"])
        var needs: [NeedsItem] = []
        needs += Approach.needs("acme/api", OpenPR(n: 20, title: "Fix PR"), state: held)
        needs += Approach.needs("acme/api", OpenPR(n: 21, title: "Stuck PR"), state: stuck)
        needs += Approach.needs("acme/api", OpenPR(n: 22, title: "Asked PR"), state: calls)
        needs += Approach.needs("acme/api", OpenPR(n: 23, title: "Big PR"), state: nil, split: split)
        needs += Approach.needs("acme/api", OpenPR(n: 25, title: "Slow PR"), state: nil, nudges: [(login: "gadi", hours: 26)])
        needs += Approach.needs("acme/api", OpenPR(n: 26, title: "Ready PR"), state: nil, landable: true)
        needs += [try XCTUnwrap(Approach.revertNeed(broke))]
        snap.approach = ApproachSnapshot(updated: t0, planes: [], needs: needs, queued: 0)
        snap.prStates = ["acme/api#20": held, "acme/api#21": stuck, "acme/api#22": calls]
        snap.calls = ["acme/api#22/c1": reply, "acme/api#22/c2": ask]
        snap.splits = ["acme/api#23": split]
        snap.landed = [broke]
        return snap
    }

    private func need(_ list: [Need], _ id: String) throws -> Need {
        try XCTUnwrap(list.first { $0.id == id }, id)
    }

    func testEveryKindFromItsSource() throws {
        let list = NeedsYou.derive(try snapshot())

        let review = try need(list, "acme/web#10/review")
        XCTAssertEqual(review.kind, .reviewReady(.changes))
        XCTAssertEqual(review.action, .post)
        XCTAssertTrue(review.outward)
        XCTAssertEqual(review.author, "ines")
        XCTAssertEqual(review.title, "Held review")

        let large = try need(list, "acme/web#11/size")
        XCTAssertEqual(large.kind, .tooLarge(lines: 12_480))
        XCTAssertEqual(large.action, .reviewAnyway)
        XCTAssertFalse(large.outward, "the repo holds reviews as drafts, so reviewing posts nothing")
        XCTAssertNil(list.first { $0.id == "acme/web#13/size" }, "a carried size skip is not offered again")
        XCTAssertNil(list.first { $0.number == 12 }, "a posted review needs nothing")

        let fix = try need(list, "acme/api#20/held")
        XCTAssertEqual(fix.kind, .fixReady)
        XCTAssertEqual(fix.action, .push)
        XCTAssertTrue(fix.outward)
        XCTAssertEqual(fix.reason, "Fixed the flaky date test")
        XCTAssertNil(fix.author, "the user's own PR")

        let stuck = try need(list, "acme/api#21/stuck")
        XCTAssertEqual(stuck.kind, .stuck)
        XCTAssertEqual(stuck.action, .retry)
        XCTAssertFalse(stuck.outward, "trying again stays on this Mac")
        XCTAssertEqual(stuck.reason, "Tried twice; the error is in generated code")

        let reply = try need(list, "acme/api#22/c1")
        XCTAssertEqual(reply.kind, .replyReady(to: "gadi"))
        XCTAssertEqual(reply.action, .reply)
        XCTAssertTrue(reply.outward)
        XCTAssertEqual(reply.reason, "Why not cache this?")
        XCTAssertEqual(try need(list, "acme/api#22/c2").kind, .question(from: "noa"))

        let split = try need(list, "acme/api#23/split")
        XCTAssertEqual(split.kind, .splitProposed(parts: 2))
        XCTAssertEqual(split.action, .reviewSplit)
        XCTAssertFalse(split.outward)

        let wait = try need(list, "acme/api#25/wait-gadi")
        XCTAssertEqual(wait.kind, .waitingOnReviewer(login: "gadi", hours: 26))
        XCTAssertEqual(wait.action, .ping)
        XCTAssertTrue(wait.outward, "a ping comments on GitHub as the user")

        let merge = try need(list, "acme/api#26/land")
        XCTAssertEqual(merge.kind, .readyToMerge)
        XCTAssertEqual(merge.action, .merge)
        XCTAssertTrue(merge.outward)

        let revert = try need(list, "acme/api#24/revert")
        XCTAssertEqual(revert.kind, .mainBroke(failing: ["lint"]))
        XCTAssertEqual(revert.action, .revert)
        XCTAssertTrue(revert.outward)

        XCTAssertEqual(list.count, 10)
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "ids are unique")
    }

    func testOldestFirstThenUntimedInSourceOrder() throws {
        let ids = NeedsYou.derive(try snapshot()).map(\.id)
        XCTAssertEqual(Array(ids.prefix(7)), ["acme/api#24/revert", "acme/api#20/held", "acme/api#22/c1", "acme/api#22/c2",
                                              "acme/api#23/split", "acme/web#10/review", "acme/web#11/size"])
        XCTAssertEqual(Array(ids.suffix(3)), ["acme/api#21/stuck", "acme/api#25/wait-gadi", "acme/api#26/land"])
    }

    func testReviewAnywayIsAHoldWhenTheRepoPosts() throws {
        var snap = try snapshot()
        snap.config?.repos[0].posting = .comment
        XCTAssertTrue(try need(NeedsYou.derive(snap), "acme/web#11/size").outward)
        snap.config?.dryRun = true
        XCTAssertFalse(try need(NeedsYou.derive(snap), "acme/web#11/size").outward)
    }

    /// A call item whose call is gone from disk (answered, or the snapshot is stale) still reads as a question, with the
    /// item's own detail as the reason: never a blank one.
    func testCallWithNoCallDataIsNeverBlank() {
        var snap = Snapshot()
        snap.approach = ApproachSnapshot(updated: t0, planes: [], needs: [
            NeedsItem(id: "acme/api#30/c9", slug: "acme/api", n: 30, title: "Asked", kind: "call", detail: "Reviewer asked about caching"),
        ], queued: 0)
        let need = NeedsYou.derive(snap)[0]
        XCTAssertEqual(need.kind, .question(from: ""))
        XCTAssertEqual(Copy.label(need.kind), "Needs your answer")
        XCTAssertEqual(Copy.reason(need), "Reviewer asked about caching.")
        let bare = Need(id: need.id, kind: need.kind, repo: need.repo, number: need.number, title: need.title, author: nil,
                        reason: "", action: need.action, outward: need.outward, since: nil)
        XCTAssertEqual(Copy.reason(bare), "A question on this PR waits on you.")
    }

    func testEmptySnapshotNeedsNothing() {
        XCTAssertEqual(NeedsYou.derive(Snapshot()), [])
    }

    /// The bug 2.0 fixes: the Dock, menu bar, sidebar, Now and popover each counted something else. Now they all read
    /// the store's one list.
    @MainActor
    func testOneCountEverywhere() throws {
        let store = Store(snapshot: try snapshot())
        XCTAssertEqual(store.needsCount, 10)
        XCTAssertEqual(store.needsYou, NeedsYou.derive(store.snap))
        XCTAssertEqual(store.status, .needs(count: 10))
    }
}
