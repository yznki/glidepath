import XCTest
@testable import Glidepath

final class StateTests: XCTestCase {
    var home: String!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("rr-state-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    func testFailedSweepCarriesLastVerdictWithItsRunStart() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var older = RunState.new(id: "older", now: t0.addingTimeInterval(-3600))
        try older.setPR(repo: "acme/api", n: 5, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil)
        older.finish(at: t0, error: nil)
        var old = RunState.new(id: "old", now: t0)
        try old.setPR(repo: "acme/api", n: 5, stage: nil, author: "ines", title: "T", verdict: .changes, reason: "missing test")
        old.finish(at: t0, error: nil)
        var now = RunState.new(id: "now", now: t0.addingTimeInterval(60))
        try now.setPR(repo: "acme/api", n: 5, stage: nil, author: "ines", title: "T", verdict: nil, reason: nil)
        try now.setPR(repo: "acme/api", n: 6, stage: nil, author: "tom", title: "U", verdict: nil, reason: nil)
        now.carryOver(from: [older, old])

        let carried = try XCTUnwrap(now.repos[0].prs.first { $0.n == 5 })
        XCTAssertEqual(carried.verdict, .changes, "the newest earlier verdict wins")
        XCTAssertEqual(carried.reason, "missing test")
        XCTAssertEqual(carried.carriedFrom, t0, "the row shows the start of the run that decided it")
        let fresh = try XCTUnwrap(now.repos[0].prs.first { $0.n == 6 })
        XCTAssertNil(fresh.verdict, "a PR with no earlier verdict stays without one")
        XCTAssertNil(fresh.carriedFrom)

        var later = RunState.new(id: "later", now: t0.addingTimeInterval(120))
        try later.setPR(repo: "acme/api", n: 5, stage: nil, author: nil, title: nil, verdict: nil, reason: nil)
        later.carryOver(from: [now, old])
        XCTAssertEqual(later.repos[0].prs[0].carriedFrom, t0, "carrying again keeps the original start")
    }

    func testReviewRunCarriesOtherRowsAndLeavesTheTargetToItself() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var sweep = RunState.new(id: "sweep", now: t0)
        try sweep.setPR(repo: "acme/api", n: 1, stage: nil, author: "ines", title: "one", verdict: .approve, reason: nil)
        try sweep.setPR(repo: "acme/api", n: 2, stage: nil, author: "bo", title: "two", verdict: .changes, reason: "fix it")
        try sweep.setPR(repo: "acme/web", n: 9, stage: nil, author: "cy", title: "nine", verdict: .approve, reason: nil)
        sweep.finish(at: t0, error: nil)

        var review = RunState.new(id: "review", now: t0.addingTimeInterval(60), kind: "review")
        review.carryRows(from: sweep)
        XCTAssertEqual(review.kind, "review")
        XCTAssertEqual(review.repos.map(\.slug), ["acme/api", "acme/web"])
        XCTAssertEqual(review.repos[0].prs.map(\.n), [1, 2])
        XCTAssertEqual(review.repos[0].prs[0].verdict, .approve)
        XCTAssertEqual(review.repos[0].prs[0].carriedFrom, t0, "a carried row says when it was decided")
        XCTAssertEqual(review.repos[1].prs.map(\.n), [9])
        // The target is written by this run, so its carried row is dropped first.
        review.dropCarried(repo: "acme/api", numbers: [2])
        XCTAssertEqual(review.repos[0].prs.map(\.n), [1])
        XCTAssertNoThrow(try review.setPR(repo: "acme/api", n: 2, stage: nil, author: "bo", title: "two",
                                          verdict: .changes, reason: "new"))
    }

    func testDropCarriedOnlyTouchesCarriedRowsInThatRepo() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var sweep = RunState.new(id: "sweep", now: t0)
        try sweep.setPR(repo: "a/x", n: 1, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil)
        try sweep.setPR(repo: "a/x", n: 2, stage: nil, author: "ines", title: "two", verdict: .changes, reason: nil)
        try sweep.setPR(repo: "b/y", n: 1, stage: nil, author: "bo", title: "other", verdict: .approve, reason: nil)
        sweep.finish(at: t0, error: nil)

        var review = RunState.new(id: "review", now: t0.addingTimeInterval(60), kind: "review")
        review.carryRows(from: sweep)
        review.dropCarried(repo: "a/x", numbers: [1])
        XCTAssertEqual(review.repos[0].prs.map(\.n), [2], "a/x #1 is written fresh, so only it is dropped")
        XCTAssertEqual(review.repos[1].prs.map(\.n), [1], "b/y #1 is kept: its repo is not processed")
        // Without the drop, the carried a/x #1 has a verdict and this throws "already has verdict".
        XCTAssertNoThrow(try review.setPR(repo: "a/x", n: 1, stage: nil, author: nil, title: nil,
                                          verdict: .approve, reason: nil))
    }

    func testHeldDraftsShowFromAnyRunAndKeepTheirRow() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var run = RunState.new(id: "now", now: t0)
        try run.setPR(repo: "acme/api", n: 1, stage: nil, author: "ines", title: "one", verdict: .approve, reason: nil)
        try run.setPR(repo: "acme/api", n: 2, stage: nil, author: "bo", title: "two", verdict: .changes, reason: nil)
        run.setDraft(repo: "acme/api", n: 2, draft: true, posted: nil)
        run.finish(at: t0, error: nil)
        let found = [
            Drafts.Found(runId: "old", path: "", draft: DraftFile(slug: "acme/api", n: 2, head: "h", event: "REQUEST_CHANGES",
                                                                  body: "b", comments: [], created: t0)),
            Drafts.Found(runId: "old", path: "", draft: DraftFile(slug: "acme/web", n: 5, head: "h", event: "APPROVE",
                                                                  body: "b", comments: [], created: t0,
                                                                  title: "Five", author: "dee")),
        ]
        run.showDrafts(found)
        XCTAssertEqual(run.repos[0].prs.map(\.draft), [false, true])
        let added = try XCTUnwrap(run.repos[1].prs.first)
        XCTAssertEqual(added.n, 5)
        XCTAssertEqual(added.title, "Five")
        XCTAssertEqual(added.verdict, .approve)
        XCTAssertEqual(added.draft, true)
        // Its run was replaced, so the row is carried: the digest leaves it out, and the row says when it was held.
        XCTAssertEqual(added.carriedFrom, t0)
        run.showDrafts([])
        XCTAssertEqual(run.repos[0].prs.map(\.draft), [false, false], "a draft that is gone is no longer marked")
    }

    func testStagesMoveForwardOnly() throws {
        var run = RunState.new(id: "r1", now: Date())
        try run.setPR(repo: "a/b", n: 7, stage: .gather, author: "x", title: "t", verdict: nil, reason: nil)
        try run.setPR(repo: "a/b", n: 7, stage: .check, author: nil, title: nil, verdict: nil, reason: nil)
        XCTAssertThrowsError(try run.setPR(repo: "a/b", n: 7, stage: .review, author: nil, title: nil, verdict: nil, reason: nil))
        let pr = run.repos[0].prs[0]
        XCTAssertEqual(pr.stage, .check)
        XCTAssertEqual(pr.author, "x")
        XCTAssertTrue(pr.active)
    }

    func testVerdictIsFinal() throws {
        var run = RunState.new(id: "r1", now: Date())
        try run.setPR(repo: "a/b", n: 7, stage: .post, author: nil, title: nil, verdict: .changes, reason: "missing test")
        try run.setPR(repo: "a/b", n: 7, stage: nil, author: nil, title: nil, verdict: .changes, reason: nil)
        XCTAssertThrowsError(try run.setPR(repo: "a/b", n: 7, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil))
        let pr = run.repos[0].prs[0]
        XCTAssertEqual(pr.verdict, .changes)
        XCTAssertEqual(pr.reason, "missing test")
        XCTAssertFalse(pr.active)
    }

    func testSkipVerdictNeedsSkippedAndAReason() throws {
        XCTAssertNil(try StateCommand.skipVerdict([:], reason: nil))
        XCTAssertEqual(try StateCommand.skipVerdict(["--verdict": "skipped"], reason: "diff too large"), .skipped)
        XCTAssertThrowsError(try StateCommand.skipVerdict(["--verdict": "skipped"], reason: nil))
        XCTAssertThrowsError(try StateCommand.skipVerdict(["--verdict": "skipped"], reason: ""))
        XCTAssertThrowsError(try StateCommand.skipVerdict(["--verdict": "approve"], reason: "ok"))
        XCTAssertThrowsError(try StateCommand.skipVerdict(["--verdict": "changes"], reason: "ok"))
    }

    func testSkippedRowShowsItsReasonAndKeepsItsVerdict() throws {
        var run = RunState.new(id: "r1", now: Date())
        try run.setPR(repo: "a/b", n: 7, stage: .review, author: nil, title: nil, verdict: nil, reason: nil)
        try run.setPR(repo: "a/b", n: 7, stage: nil, author: nil, title: nil, verdict: .skipped, reason: "diff too large")
        var pr = run.repos[0].prs[0]
        XCTAssertEqual(pr.verdict, .skipped)
        XCTAssertEqual(pr.reason, "diff too large")
        XCTAssertFalse(pr.active)
        // A stamped row keeps its verdict and reason; a different verdict is refused.
        try run.setPR(repo: "a/b", n: 7, stage: nil, author: nil, title: nil, verdict: .skipped, reason: "other")
        XCTAssertEqual(run.repos[0].prs[0].reason, "diff too large")
        XCTAssertThrowsError(try run.setPR(repo: "a/b", n: 7, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil))
        pr = run.repos[0].prs[0]
        XCTAssertEqual(pr.verdict, .skipped)
    }

    func testFinishedRunRejectsWrites() throws {
        var run = RunState.new(id: "r1", now: Date())
        run.finish(at: Date(), error: nil)
        XCTAssertThrowsError(try run.setPR(repo: "a/b", n: 1, stage: .gather, author: nil, title: nil, verdict: nil, reason: nil))
    }

    func testSaveLoadAndCurrentSymlink() throws {
        let paths = Paths(home: home)
        let store = RunStore(paths: paths)
        var run = RunState.new(id: "20261021-100000-abc", now: Date(timeIntervalSince1970: 1_800_000_000))
        try run.setPR(repo: "a/b", n: 3, stage: .review, author: "x", title: "T", verdict: nil, reason: nil)
        try store.save(run)
        try store.makeCurrent(run.id)

        let loaded = try XCTUnwrap(try store.loadCurrent())
        XCTAssertEqual(loaded.id, run.id)
        XCTAssertEqual(loaded.started.timeIntervalSince1970, 1_800_000_000, accuracy: 1)
        XCTAssertEqual(loaded.repos, run.repos)

        // Re-pointing current and saving again leaves no temp files behind.
        let second = RunState.new(id: "second", now: Date())
        try store.save(second)
        try store.makeCurrent(second.id)
        XCTAssertEqual(try store.loadCurrent()?.id, "second")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.stateDir)
            .filter { $0.hasPrefix(".current") }
        XCTAssertEqual(leftovers, [])
        let runFiles = try FileManager.default.contentsOfDirectory(atPath: paths.runsDir).sorted()
        XCTAssertEqual(runFiles, ["20261021-100000-abc.json", "second.json"])
    }

    func testLockIsExclusiveAndReleasedOnDeinit() throws {
        let path = home + "/state/run.lock"
        var lock: RunLock? = try XCTUnwrap(try RunLock.acquire(path))
        XCTAssertTrue(RunLock.isHeld(path))
        XCTAssertNil(try RunLock.acquire(path))
        lock = nil
        XCTAssertFalse(RunLock.isHeld(path))
        _ = lock
    }

    func testTwentyParallelStateSetsAllLand() throws {
        let paths = Paths(home: home)
        let store = RunStore(paths: paths)
        let id = "parallel"
        try store.save(RunState.new(id: id, now: Date()))
        let failures = AtomicCounter()
        DispatchQueue.concurrentPerform(iterations: 20) { i in
            do {
                try store.mutate(id) { run in
                    try run.setPR(repo: "a/b", n: i + 1, stage: .gather, author: "x", title: nil,
                                  verdict: nil, reason: nil)
                }
            } catch {
                failures.add()
            }
        }
        XCTAssertEqual(failures.value, 0)
        let run = try store.load(id)
        XCTAssertEqual(Set(run.repos[0].prs.map(\.n)), Set(1...20))
    }
}

final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }

    /// A 1.0.x run file has none of the 1.1.0 fields. It must still decode, with them empty.
    func testOneZeroRunFileDecodesWithoutNewFields() throws {
        let json = """
        {"error": null, "finished": "2026-10-20T10:14:00Z", "id": "20261020-101200-abc123", "repos": [
          {"error": null, "prs": [
            {"active": false, "n": 5, "reason": "missing test", "stage": "post", "tokens": 1200,
             "verdict": "changes", "author": "ines", "title": "T"}
          ], "slug": "acme/api"}
        ], "started": "2026-10-20T10:12:00Z", "tokens": 1200}
        """
        let run = try RunStore.decoder().decode(RunState.self, from: Data(json.utf8))
        let pr = try XCTUnwrap(run.repos.first?.prs.first)
        XCTAssertEqual(pr.verdict, .changes)
        XCTAssertNil(pr.draft)
        XCTAssertNil(pr.flagged)
        XCTAssertNil(pr.posted)
    }

    func testDraftAndFlagFieldsRoundTrip() throws {
        var run = RunState.new(id: "r", now: Date(timeIntervalSince1970: 1_800_000_000))
        try run.setPR(repo: "acme/api", n: 5, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil)
        try run.setFlagged(repo: "acme/api", n: 5)
        run.setDraft(repo: "acme/api", n: 5, draft: true, posted: nil)
        let data = try RunStore.encoder().encode(run)
        let back = try RunStore.decoder().decode(RunState.self, from: data)
        XCTAssertEqual(back, run)
        XCTAssertEqual(back.repos[0].prs[0].draft, true)
        XCTAssertEqual(back.repos[0].prs[0].flagged, true)
    }

    func testRunWithoutIsDraftPRKeyStillDecodes() throws {
        let json = """
        {"id":"old","started":"2026-01-01T00:00:00Z","repos":[{"slug":"acme/api","prs":[
          {"n":5,"stage":"post","active":false,"tokens":0}]}],"tokens":0}
        """
        let run = try RunStore.decoder().decode(RunState.self, from: Data(json.utf8))
        XCTAssertNil(run.repos[0].prs[0].isDraftPR)
        XCTAssertFalse(Presentation.strips(from: run)[0].isDraftPR)
    }

    func testUnstampedKeptPRsGetAReasonUnlessTheSessionLeftOne() throws {
        var run = RunState.new(id: "r", now: Date(timeIntervalSince1970: 1_800_000_000))
        try run.setPR(repo: "acme/api", n: 1, stage: nil, author: nil, title: nil, verdict: nil, reason: nil)
        try run.setPR(repo: "acme/api", n: 2, stage: nil, author: nil, title: nil, verdict: nil, reason: nil)
        try run.setPR(repo: "acme/api", n: 3, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil)
        try run.setNote(repo: "acme/api", n: 2, note: "diff unavailable")
        run.noteUnstamped(repo: "acme/api", numbers: [1, 2, 3], reason: "review session ended without a verdict; see the log")
        let prs = run.repos[0].prs
        XCTAssertEqual(prs.map(\.reason), ["review session ended without a verdict; see the log", "diff unavailable", nil])
        XCTAssertNil(prs[0].verdict)
        XCTAssertEqual(prs[2].verdict, .approve)
    }
}
