import XCTest
@testable import ReviewRadar

final class PresentationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func strip(_ n: Int, repo: String = "acme/api", stage: Int = 1, active: Bool = false,
               verdict: Verdict? = nil) -> Strip {
        Strip(repo: repo, number: n, author: "ines", title: "T\(n)", reason: nil, stage: stage,
              active: active, verdict: verdict, tokens: 0)
    }

    func run(_ prs: [PRState], finished: Bool = false, error: String? = nil, repos: [String] = ["acme/api"]) -> RunState {
        RunState(id: "r", started: now, finished: finished ? now : nil,
                 repos: repos.map { RepoState(slug: $0, prs: $0 == repos[0] ? prs : [], error: nil) },
                 tokens: 0, error: error)
    }

    func pr(_ n: Int, stage: Stage = .gather, active: Bool = false, verdict: Verdict? = nil) -> PRState {
        PRState(n: n, author: "ines", title: "T", stage: stage, active: active, verdict: verdict,
                reason: nil, tokens: 0)
    }

    func testHeaderKinds() {
        var snap = Snapshot(run: run([pr(1, active: true), pr(2, verdict: .changes), pr(3, verdict: .approve)]),
                            running: true, jobInstalled: true)
        guard case .running(let changes, let reviewing, let total, let landed, _, _) = Presentation.headerKind(snap, now: now) else {
            return XCTFail("expected running")
        }
        XCTAssertEqual([changes, reviewing, total, landed], [1, 1, 3, 2])

        snap.running = false
        snap.paused = true
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .paused(since: nil))

        snap.paused = false
        snap.run = run([], finished: true)
        XCTAssertEqual(Presentation.headerKind(snap, now: now),
                       .emptyRun(repos: 1, checkedAt: now, next: nil))

        snap.run = run([pr(1, verdict: .changes)], finished: true)
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .idle(changes: 1, next: nil))

        snap.run = run([pr(1, verdict: .approve)], finished: true, error: "claude exited 1\nsee log")
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .failed(message: "claude exited 1"))

        snap.run = nil
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .noSweeps(next: nil))

        snap.jobInstalled = false
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .notScheduled)
    }

    func testRowOrderIsChangesActiveApprovedSkippedDropped() {
        let strips = [
            strip(5, verdict: .skipped), strip(4, verdict: .approve), strip(3, stage: 2, active: true),
            strip(2, verdict: .changes), strip(1, verdict: nil),
        ]
        let groups = Presentation.rows(from: strips, running: false,
                                       repos: [RepoState(slug: "acme/api", prs: [], error: nil)])
        XCTAssertEqual(groups[0].rows.map { $0.strip.number }, [2, 3, 4, 5, 1])
    }

    func testRailSegments() {
        XCTAssertEqual(Presentation.rail(strip(1, stage: 3, active: true), running: true),
                       [.done, .done, .current, .future])
        XCTAssertEqual(Presentation.rail(strip(1, verdict: .approve), running: true), [.done, .done, .done, .done])
        XCTAssertNil(Presentation.rail(strip(1, verdict: .skipped), running: true))
        XCTAssertNil(Presentation.rail(strip(1), running: false), "dropped rows show no rail")
        XCTAssertEqual(Presentation.rail(strip(1), running: true), [.future, .future, .future, .future])
    }

    func testRadarProgress() {
        XCTAssertEqual(Presentation.progress(strip(1)), 1.0, "queued sits on the outer ring")
        XCTAssertEqual(Presentation.progress(strip(1, stage: 1, active: true)), 0.8)
        XCTAssertEqual(Presentation.progress(strip(1, stage: 4, active: true)), 0.3)
        XCTAssertEqual(Presentation.progress(strip(1, verdict: .changes)), 0.18)
    }

    func testPausedSinceReadsTheMarker() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rr-pause-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let paths = Paths(home: home)
        try Pause.set(true, paths)
        XCTAssertNotNil(Pause.since(paths))
        try Pause.set(false, paths)
        XCTAssertNil(Pause.since(paths))
    }
}
