import XCTest
@testable import ReviewRadar

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
}
