import XCTest
@testable import Glidepath

/// A sweep that has started but recorded no PRs yet says "Getting ready", never "0 of 0".
final class PreparingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func run(phase: String?, prs: [PRState] = []) -> RunState {
        var r = RunState(id: "r", started: now, finished: nil,
                         repos: [RepoState(slug: "acme/api", prs: prs, error: nil)], tokens: 0, error: nil)
        r.phase = phase
        return r
    }

    func testEmptyRunningSweepIsPreparing() {
        let snap = Snapshot(run: run(phase: "indexing acme/api"), running: true, jobInstalled: true)
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .preparing(phase: "indexing acme/api", started: now))
    }

    func testRecordedPRsLeavePreparing() {
        let pr = PRState(n: 1, author: "ines", title: "T", stage: .gather, active: true, verdict: nil,
                         reason: nil, tokens: 0)
        let snap = Snapshot(run: run(phase: nil, prs: [pr]), running: true, jobInstalled: true)
        guard case .running = Presentation.headerKind(snap, now: now) else { return XCTFail("expected running") }
    }

    func testPhaseLines() {
        XCTAssertEqual(Presentation.preparingLine("indexing acme/api"), "Refreshing the code graph for acme/api")
        XCTAssertEqual(Presentation.preparingLine("listing PRs in acme/api"), "Listing open PRs in acme/api")
        XCTAssertEqual(Presentation.preparingLine(nil), "Listing open PRs")
    }

    func testPopoverCopy() {
        let copy = HeaderCopy.make(.preparing(phase: "indexing acme/api", started: now), now: now)
        XCTAssertEqual(copy.headline, "Getting ready")
        XCTAssertEqual(copy.line2, "Refreshing the code graph for acme/api")
        XCTAssertFalse(copy.headline.contains("0 in flight"))
    }

    func testOldRunFilesDecodeWithoutPhase() throws {
        let json = #"{"id":"r","started":"2027-01-15T08:00:00Z","repos":[],"tokens":0}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(RunState.self, from: json)
        XCTAssertNil(old.phase)
    }

    func testFinishClearsPhase() {
        var r = run(phase: "indexing acme/api")
        r.finish(at: now, error: nil)
        XCTAssertNil(r.phase)
    }
}
