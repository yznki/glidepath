import XCTest
@testable import Glidepath

final class LandingTests: XCTestCase {
    let home = "/fake/home"
    let base = "schedule = [\"07:00\"]\n"
    let pass = CheckState(name: "test", status: "COMPLETED", conclusion: "SUCCESS")

    /// A PR that is approved, clean and passing, based on main.
    func pr(_ n: Int, branch: String, base: String = "main") -> OpenPR {
        OpenPR(n: n, title: "PR \(n)", url: "https://github.com/acme/api/pull/\(n)", reviewDecision: "APPROVED",
               mergeStateStatus: "CLEAN", branch: branch, head: "sha\(n)", base: base, defaultBranch: "main",
               checks: [pass])
    }

    // MARK: Config

    func testMergeParsesOffByDefaultAndRejectsBadValues() throws {
        let c = try Config.parse(base, home: home)
        XCTAssertEqual(c.tend.merge, .off)
        XCTAssertEqual(try Config.parse(base + "[tend]\nmerge = \"auto\"\n", home: home).tend.merge, .auto)
        XCTAssertEqual(try Config.parse(base + "[tend]\nmerge = \"ask\"\n", home: home).tend.merge, .ask)
        XCTAssertThrowsError(try Config.parse(base + "[tend]\nmerge = \"yes\"\n", home: home))
        XCTAssertThrowsError(try Config.parse(base + "[tend]\nmerge = true\n", home: home))
    }

    func testMergeMethodDefaultsToMergeAndRejectsUnknown() throws {
        let plain = try Config.parse(base + "[[repo]]\nslug = \"acme/api\"\n", home: home)
        XCTAssertEqual(plain.repos[0].mergeMethod, .merge)
        let squash = try Config.parse(base + "[[repo]]\nslug = \"acme/api\"\nmerge_method = \"squash\"\n", home: home)
        XCTAssertEqual(squash.repos[0].mergeMethod, .squash)
        XCTAssertThrowsError(try Config.parse(base + "[[repo]]\nslug = \"acme/api\"\nmerge_method = \"ff\"\n", home: home))
    }

    func testMergeSettingsRoundTripAndDefaultsWriteNothing() throws {
        XCTAssertFalse(try Config.parse(base, home: home).render().contains("merge"))
        var c = try Config.parse(base + "[[repo]]\nslug = \"acme/api\"\n", home: home)
        c = ConfigEditor.setTendMerge(c, .ask)
        c.repos[0].mergeMethod = .rebase
        let text = c.render()
        XCTAssertTrue(text.contains("merge = \"ask\""))
        XCTAssertTrue(text.contains("merge_method = \"rebase\""))
        XCTAssertEqual(try Config.parse(text, home: home), c)
    }

    func testSetTendEnabledWritesAskWhenLandingIsOff() throws {
        let start = try Config.parse(base, home: home)
        var c = ConfigEditor.setTendEnabled(start, true)
        XCTAssertEqual(c.tend.merge, .ask)
        XCTAssertEqual(c.tend.advisor, .opus)
        c = ConfigEditor.setTendMerge(c, .auto)
        c = ConfigEditor.setTendEnabled(ConfigEditor.setTendEnabled(c, false), true)
        XCTAssertEqual(c.tend.merge, .auto, "a landing setting already chosen is kept")
        XCTAssertEqual(ConfigEditor.setTendMerge(c, .off).tend.merge, .off)
    }

    // MARK: Autopilot

    func testAutopilotLandConflictAndRevertAcrossSettings() {
        for autopilot in [false, true] {
            for merge in TendMerge.allCases {
                let landActor: Actor = autopilot || merge == .auto ? .act : .you
                XCTAssertEqual(Autopilot.actor(.land, autopilot: autopilot, push: .untilApproved, merge: merge), landActor,
                               "land autopilot=\(autopilot) merge=\(merge)")
                XCTAssertEqual(Autopilot.actor(.conflict, autopilot: autopilot, push: .untilApproved, merge: merge),
                               autopilot ? .council : .you)
                XCTAssertEqual(Autopilot.actor(.revert, autopilot: autopilot, push: .untilApproved, merge: merge),
                               autopilot ? .council : .you)
            }
        }
        // Autopilot lands even with merge off; without it, a default-off call gets the user.
        XCTAssertEqual(Autopilot.actor(.land, autopilot: true, push: .always), .act)
        XCTAssertEqual(Autopilot.actor(.land, autopilot: false, push: .always), .you)
    }

    // MARK: Landing

    func testReadyNeedsApprovalCleanBaseAndNothingWaiting() {
        let a = pr(1, branch: "a")
        XCTAssertTrue(Landing.ready(a, nil))
        var unapproved = a
        unapproved.reviewDecision = nil
        XCTAssertFalse(Landing.ready(unapproved, nil))
        XCTAssertFalse(Landing.ready(a, TendPR(slug: "acme/api", n: 1).with { $0.held = TendHeld(commit: "c", summary: "s", at: Date()) }))
        XCTAssertFalse(Landing.ready(a, TendPR(slug: "acme/api", n: 1).with { $0.stuck = "Conflicts" }))
        XCTAssertFalse(Landing.ready(a, TendPR(slug: "acme/api", n: 1).with { $0.calls = [YourCall(id: "t", kind: "thread", author: "al", quote: "q", draft: nil, at: Date())] }))
        XCTAssertFalse(Landing.ready(a, TendPR(slug: "acme/api", n: 1).with { $0.off = true }))
        var stacked = a
        stacked.base = "other"
        XCTAssertFalse(Landing.ready(stacked, nil))
        var unknownDefault = a
        unknownDefault.defaultBranch = ""
        XCTAssertFalse(Landing.ready(unknownDefault, nil))
        var fork = a
        fork.isFork = true
        XCTAssertFalse(Landing.ready(fork, nil), "a fork's PR never lands")
    }

    func testNextIsLowestReadyNumberAndChildrenFollowTheBranch() {
        let a = pr(1, branch: "a")
        var b = pr(2, branch: "b")
        b.reviewDecision = nil
        let c = pr(3, branch: "c")
        let child = pr(5, branch: "e", base: "a")
        let grandchild = pr(6, branch: "f", base: "e")
        let prs = [c, child, b, a, grandchild]
        XCTAssertEqual(Landing.next(prs, states: [:])?.n, 1)
        XCTAssertEqual(Landing.next(prs, states: [1: TendPR(slug: "acme/api", n: 1).with { $0.held = TendHeld(commit: "c", summary: "s", at: Date()) }])?.n, 3)
        XCTAssertNil(Landing.next([b], states: [:]))
        XCTAssertEqual(Landing.children(of: a, in: prs).map(\.n), [5])
        XCTAssertEqual(Landing.children(of: child, in: prs).map(\.n), [6])
        XCTAssertEqual(Landing.children(of: c, in: prs), [])
    }

    func testDetailNamesTheChecksAndTheStackAbove() {
        let a = pr(1, branch: "a")
        let prs = [a, pr(5, branch: "e", base: "a"), pr(6, branch: "f", base: "e"), pr(9, branch: "z")]
        XCTAssertEqual(Landing.detail(a, prs), "Ready to land · approved · 1 checks green · then #5, #6")
        XCTAssertEqual(Landing.detail(a, [a]), "Ready to land · approved · 1 checks green")
        var bare = a
        bare.checks = []
        XCTAssertEqual(Landing.detail(bare, [bare]), "Ready to land · approved")
    }

    func testMainWatchVerdicts() {
        func check(_ name: String, _ conclusion: String?, running: Bool = false) -> CheckState {
            CheckState(name: name, status: running ? "IN_PROGRESS" : "COMPLETED", conclusion: conclusion)
        }
        XCTAssertEqual(MainWatch.verdict(merge: [check("test", "SUCCESS")], parent: [check("test", "SUCCESS")]), .ok)
        XCTAssertEqual(MainWatch.verdict(merge: [check("test", nil, running: true)], parent: [check("test", "SUCCESS")]), .pending)
        XCTAssertEqual(MainWatch.verdict(merge: [], parent: [check("test", "SUCCESS")]), .pending, "no checks yet is not green")
        XCTAssertEqual(MainWatch.verdict(merge: [check("lint", "FAILURE")], parent: [check("lint", "SUCCESS")]), .broke(["lint"]))
        XCTAssertEqual(MainWatch.verdict(merge: [check("lint", "TIMED_OUT")], parent: [check("lint", "SUCCESS")]), .broke(["lint"]))
        // Failing on both sides was already broken: not this merge's fault.
        XCTAssertEqual(MainWatch.verdict(merge: [check("lint", "FAILURE")], parent: [check("lint", "FAILURE")]), .ok)
        // A new check that fails has no passing parent to compare with: not a break.
        XCTAssertEqual(MainWatch.verdict(merge: [check("new", "FAILURE")], parent: []), .ok)
        // A cancelled check is not a failure, and a failure waits until every check on the merge commit has finished.
        XCTAssertEqual(MainWatch.verdict(merge: [check("lint", "CANCELLED")], parent: [check("lint", "SUCCESS")]), .ok)
        XCTAssertEqual(MainWatch.verdict(merge: [check("lint", "FAILURE"), check("test", nil, running: true)],
                                         parent: [check("lint", "SUCCESS")]), .pending)
    }

    func testRevertBodyNamesTheChecks() {
        XCTAssertEqual(Landing.revertBody(n: 12, sha: "abc1234def5678", failing: ["lint", "test"]),
                       "Reverts #12 (`abc1234`). lint, test failed on the merge commit and passed on the commit before it.")
    }

    func testLandedRecordsAndRevertNeed() throws {
        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-landing-\(UUID().uuidString)", env: [:])
        let store = TendStore(paths: paths)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let recent = TendLanded(slug: "acme/api", n: 4, title: "Fix", sha: "abc", parent: "def", at: now, status: "watching")
        let old = TendLanded(slug: "acme/api", n: 3, title: "Old", sha: "aaa", parent: "bbb",
                             at: now.addingTimeInterval(-8 * 86_400), status: "ok")
        XCTAssertEqual(store.loadLanded(), [])
        try store.saveLanded([recent, old])
        XCTAssertEqual(store.loadLanded(), [recent], "entries older than 7 days are dropped on save")
        XCTAssertEqual(store.all(), [], "landed.json is not a PR's state file")

        let watching = Approach.landedPlane(recent, lane: 2)
        XCTAssertEqual(watching.phase, .landed)
        XCTAssertEqual(watching.marker, 4)
        XCTAssertEqual(watching.label, "Landed · watching main")
        XCTAssertEqual(watching.lane, 2)
        XCTAssertEqual(watching.landedAt, now)
        XCTAssertNil(Approach.revertNeed(recent))

        var broke = recent
        broke.status = "broke"
        broke.failing = ["lint"]
        XCTAssertEqual(Approach.landedPlane(broke, lane: 0).label, "Main broke after #4")
        XCTAssertEqual(Approach.revertNeed(broke), NeedsItem(id: "acme/api#4/revert", slug: "acme/api", n: 4, title: "Fix",
                                                             kind: "revert", detail: "Main broke after #4 · lint"))
        broke.revert = 9
        XCTAssertNil(Approach.revertNeed(broke), "a revert already open needs nothing")
        broke.status = "reverted"
        XCTAssertEqual(Approach.landedPlane(broke, lane: 0).label, "Reverted in #9")
    }

    func testLandedRecordDecodesOlderFileWithoutNewKeys() throws {
        let text = #"{"slug":"acme/api","n":4,"title":"Fix","sha":"abc","parent":"def","at":"2026-10-26T09:00:00Z","status":"ok"}"#
        let record = try RunStore.decoder().decode(TendLanded.self, from: Data(text.utf8))
        XCTAssertEqual(record.failing, [])
        XCTAssertNil(record.revert)
    }

    func testApproachPlaneDecodesFilesWithoutLandedAt() throws {
        let text = #"{"slug":"acme/api","n":1,"title":"t","url":"u","phase":"cleared","marker":3,"label":"Ready to land","lane":0,"off":false,"gates":[],"ci":"passed"}"#
        let plane = try RunStore.decoder().decode(ApproachPlane.self, from: Data(text.utf8))
        XCTAssertNil(plane.landedAt)
        XCTAssertNil(plane.waitingOn)
        XCTAssertNil(plane.stackIndex)
    }

    // MARK: Fingerprint and decision

    func testFingerprintChangesWithMergeState() {
        let a = pr(3, branch: "c")
        var merged = a
        merged.mergeStateStatus = "BLOCKED"
        XCTAssertNotEqual(Fingerprint.full(a, me: "dev"), Fingerprint.full(merged, me: "dev"))
        var rebased = a
        rebased.base = "release"
        XCTAssertNotEqual(Fingerprint.full(a, me: "dev"), Fingerprint.full(rebased, me: "dev"))
        var undecided = a
        undecided.reviewDecision = nil
        XCTAssertNotEqual(Fingerprint.full(a, me: "dev"), Fingerprint.full(undecided, me: "dev"))
        XCTAssertEqual(Fingerprint.full(a, me: "dev"), Fingerprint.full(a, me: "dev"))
    }

    func testTendDecisionRoundsOnAConflict() {
        var c = pr(3, branch: "c")
        c.reviewDecision = nil
        c.mergeStateStatus = "DIRTY"
        var state = TendPR(slug: "acme/api", n: 3)
        XCTAssertEqual(TendDecision.decide(c, state: state, me: "dev"), .round(.normal))
        c.reviewDecision = "APPROVED"
        XCTAssertEqual(TendDecision.decide(c, state: state, me: "dev"), .round(.urgent))
        state.fingerprint = Fingerprint.full(c, me: "dev")
        XCTAssertEqual(TendDecision.decide(c, state: state, me: "dev"), .idle, "the same conflict, already tried")
        c.labels = [Approach.handsOffLabel]
        state.fingerprint = nil
        XCTAssertEqual(TendDecision.decide(c, state: state, me: "dev"), .skip("hands off"))
    }

    // MARK: Needs

    func testNeedsAddsTheLandItemWhenLandable() {
        let a = pr(1, branch: "a")
        let child = pr(2, branch: "b", base: "a")
        XCTAssertEqual(Approach.needs("acme/api", a, state: nil), [])
        XCTAssertEqual(Approach.needs("acme/api", a, state: nil, landable: false), [])
        XCTAssertEqual(Approach.needs("acme/api", a, state: nil, landable: true, prs: [a, child]), [NeedsItem(
            id: "acme/api#1/land", slug: "acme/api", n: 1, title: "PR 1", kind: "land",
            detail: "Ready to land · approved · 1 checks green · then #2")])
    }
}

private extension TendPR {
    /// Changes a copy in place and returns it, to keep the test setups short.
    func with(_ change: (inout TendPR) -> Void) -> TendPR {
        var copy = self
        change(&copy)
        return copy
    }
}
