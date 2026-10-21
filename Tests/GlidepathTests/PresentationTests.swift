import XCTest
@testable import Glidepath

final class PresentationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func strip(_ n: Int, repo: String = "acme/api", stage: Int = 1, active: Bool = false,
               verdict: Verdict? = nil, reason: String? = nil) -> Strip {
        Strip(repo: repo, number: n, author: "ines", title: "T\(n)", reason: reason, stage: stage,
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
        guard case .running(let changes, let reviewing, let total, let landed, _) = Presentation.headerKind(snap, now: now) else {
            return XCTFail("expected running")
        }
        XCTAssertEqual([changes, reviewing, total, landed], [1, 1, 3, 2])

        snap.running = false
        snap.paused = true
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .paused(since: nil, lastStarted: now))

        snap.paused = false
        snap.run = run([], finished: true)
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .emptyRun(repos: 1, next: nil, lastStarted: now))

        snap.run = run([pr(1, verdict: .changes)], finished: true)
        XCTAssertEqual(Presentation.headerKind(snap, now: now),
                       .idle(changes: 1, next: nil, lastStarted: now, total: 1))

        snap.run = run([pr(1, verdict: .approve)], finished: true, error: "claude exited 1\nsee log")
        XCTAssertEqual(Presentation.headerKind(snap, now: now),
                       .failed(reason: "The review agent stopped early (exit 1)", started: now, next: nil))

        snap.run = nil
        snap.repoCount = 2
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .noSweeps(next: nil, repos: 2))

        snap.jobInstalled = false
        XCTAssertEqual(Presentation.headerKind(snap, now: now), .notScheduled)
    }

    func testHeaderCopyForEachState() {
        let idle = HeaderCopy.make(.idle(changes: 2, next: nil, lastStarted: now, total: 7), now: now)
        XCTAssertEqual(idle.headline, "2 need changes", "no dot before a headline")
        XCTAssertEqual(idle.line2?.hasSuffix("7 PRs"), true)
        XCTAssertEqual(HeaderCopy.make(.idle(changes: 0, next: nil, lastStarted: now, total: 1), now: now).headline, "All clear")
        let running = HeaderCopy.make(.running(changes: 2, reviewing: 3, total: 7, landed: 4, started: now), now: now)
        XCTAssertEqual(running.headline, "3 in flight, 4 landed")
        XCTAssertEqual(running.line2, "2 need changes")
        XCTAssertEqual(running.line2Tone, .changes)
        XCTAssertNil(HeaderCopy.make(.running(changes: 0, reviewing: 3, total: 7, landed: 4, started: now), now: now).line2,
                     "landed count is in the headline, so line 2 stays empty without changes")
        let failed = HeaderCopy.make(.failed(reason: "x", started: now, next: nil), now: now)
        XCTAssertEqual(failed.headline, "Last sweep failed")
        XCTAssertEqual(failed.headlineTone, .error)
        XCTAssertTrue(failed.openLog)
        XCTAssertFalse(HeaderCopy.make(.paused(since: nil, lastStarted: nil), now: now).openLog)
        XCTAssertEqual(HeaderCopy.make(.noSweeps(next: nil, repos: 2), now: now).line2,
                       "Pick the repos Glidepath should review.")
        let paused = HeaderCopy.make(.paused(since: nil, lastStarted: nil), now: now)
        XCTAssertEqual(paused.headlineTone, .changes, "paused headline uses the changes colour")
    }

    func testRowFactsUsePassThreeLabels() {
        XCTAssertEqual(Presentation.phaseWords, ["Gather", "Review", "Check", "Land"])
        XCTAssertEqual(ApproachRowText.skipped("draft"), "Draft, skipped")
    }

    func testRowOrderIsChangesNoResultInFlightApprovedSkipped() {
        let strips = [
            strip(5, verdict: .skipped), strip(4, verdict: .approve), strip(3, stage: 2, active: true),
            strip(2, verdict: .changes), strip(1, verdict: nil),
        ]
        let groups = Presentation.rows(from: strips, running: false,
                                       repos: [RepoState(slug: "acme/api", prs: [], error: nil)])
        XCTAssertEqual(groups[0].rows.map { $0.strip.number }, [2, 1, 3, 4, 5])
    }

    func testInFlightRowsLeadWithTheLatestStage() {
        let strips = [strip(1, stage: 1, active: true), strip(2, stage: 3, active: true), strip(3)]
        let groups = Presentation.rows(from: strips, running: true,
                                       repos: [RepoState(slug: "acme/api", prs: [], error: nil)])
        XCTAssertEqual(groups[0].rows.map { $0.strip.number }, [2, 1, 3], "stage 3, then stage 1, then queued")
    }

    func testStatusIsOneMarkPerRow() {
        XCTAssertEqual(Presentation.status(strip(1, verdict: .changes), running: true), .changes)
        XCTAssertEqual(Presentation.status(strip(1, verdict: .approve), running: true), .approved)
        XCTAssertEqual(Presentation.status(strip(1, verdict: .skipped, reason: "draft"), running: true), .skipped(reason: "draft"))
        XCTAssertEqual(Presentation.status(strip(1, stage: 2, active: true), running: true), .active(phase: "Review"))
        XCTAssertEqual(Presentation.status(strip(1), running: true), .queued)
        XCTAssertEqual(Presentation.status(strip(1), running: false), .noResult)
        XCTAssertEqual(ApproachRowText.skipped("draft"), "Draft, skipped")
        XCTAssertNil(Presentation.meter(strip(1, verdict: .approve)), "finished rows show no meter")
        XCTAssertEqual(Presentation.meter(strip(1, stage: 3, active: true)), [.done, .done, .current, .future])
    }

    func testProfileMarksFollowTheRules() {
        let groups = Presentation.rows(from: [
            strip(1, stage: 2, active: true), strip(2, verdict: .changes), strip(3),
        ], running: true, repos: [RepoState(slug: "acme/api", prs: [], error: nil)])
        let marks = Presentation.marks(groups, running: true)
        // Rows sort changes first, then in flight with the latest stage first: #2 (changes), #1 (review), #3 (queued).
        XCTAssertEqual(marks.map(\.kind), [.landed(.changes), .active(stage: 2), .queued])
    }

    func testProfilePlacesStagesLeftToRightAndLandedOnTheRunway() {
        let marks = [
            ProfileMark(id: "a", kind: .active(stage: 1)),
            ProfileMark(id: "b", kind: .active(stage: 4)),
            ProfileMark(id: "c", kind: .landed(.approve)),
            ProfileMark(id: "d", kind: .landed(.changes)),
        ]
        let placed = Profile.place(marks, running: true)
        let a = placed.first { $0.id == "a" }!, b = placed.first { $0.id == "b" }!
        XCTAssertLessThan(a.centre.x, b.centre.x, "later stages sit further right")
        XCTAssertGreaterThanOrEqual(b.centre.x, Profile.runwayX - 40, "stage 4 is near the runway")
        let c = placed.first { $0.id == "c" }!, d = placed.first { $0.id == "d" }!
        XCTAssertEqual(c.centre.y, Profile.runwayTop(running: true) - c.side / 2, accuracy: 0.01, "marks sit on the runway")
        XCTAssertLessThan(c.centre.x, d.centre.x, "landed marks pack left to right in list order")
        XCTAssertEqual(c.side, Profile.markSide)
        XCTAssertEqual(d.centre.x - c.centre.x, Profile.markStep, accuracy: 0.01, "landed marks are 16 pt apart (6 pt gap)")
        XCTAssertEqual(c.centre.x - c.side / 2, Profile.runwayX, accuracy: 0.01, "the first mark starts at the land label")
    }

    func testSameStageCirclesSpreadApart() {
        let marks = (0..<3).map { ProfileMark(id: "p\($0)", kind: .active(stage: 2)) }
        let xs = Profile.place(marks, running: true).map(\.centre.x).sorted()
        XCTAssertEqual(xs[1] - xs[0], Profile.spread, accuracy: 0.01)
        XCTAssertEqual(xs[2] - xs[1], Profile.spread, accuracy: 0.01)
    }

    func testManyLandedSquaresShrinkToFitTheRunway() {
        let marks = (0..<10).map { ProfileMark(id: "s\($0)", kind: .landed(.approve)) }
        let placed = Profile.place(marks, running: false)
        XCTAssertLessThan(placed.map(\.side).max() ?? 0, 8)
        XCTAssertLessThanOrEqual((placed.last?.centre.x ?? 0) + (placed.last?.side ?? 0) / 2, Profile.runwayX + Profile.runwayLength + 0.01)
    }

    func testPausedSinceReadsTheMarker() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gp-pause-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let paths = Paths(home: home)
        try Pause.set(true, paths)
        XCTAssertNotNil(Pause.since(paths))
        try Pause.set(false, paths)
        XCTAssertNil(Pause.since(paths))
    }
}

/// The text the row shows for a skipped PR.
enum ApproachRowText {
    static func skipped(_ reason: String) -> String { PRRow.skippedText(reason) }
}
