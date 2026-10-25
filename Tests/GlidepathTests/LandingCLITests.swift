import XCTest
@testable import Glidepath

final class LandingCLITests: XCTestCase {
    func testMergeArgumentsPinTheMethodAndTheHead() {
        XCTAssertEqual(Tender.mergeArguments(slug: "acme/api", n: 7, method: .squash, head: "abc123"),
                       ["pr", "merge", "7", "-R", "acme/api", "--squash", "--match-head-commit", "abc123"])
        XCTAssertEqual(Tender.mergeArguments(slug: "acme/api", n: 8, method: .merge, head: "d")[5], "--merge")
    }

    func testRevertArgumentsAddTheMainlineOnlyForAMergeCommit() {
        XCTAssertEqual(Tender.revertArguments(sha: "abc", parents: 2), ["revert", "--no-edit", "-m", "1", "abc"])
        XCTAssertEqual(Tender.revertArguments(sha: "abc", parents: 1), ["revert", "--no-edit", "abc"])
    }

    func testParseCheckRunsReadsNameStatusAndConclusion() {
        let checks = Tender.parseCheckRuns("Unit Tests\tcompleted\tfailure\nBuild\tin_progress\t\n\nLint\tcompleted\tsuccess\n")
        XCTAssertEqual(checks, [
            CheckState(name: "Unit Tests", status: "COMPLETED", conclusion: "FAILURE", url: nil),
            CheckState(name: "Build", status: "IN_PROGRESS", conclusion: nil, url: nil),
            CheckState(name: "Lint", status: "COMPLETED", conclusion: "SUCCESS", url: nil),
        ])
    }

    func testWatchVerdictFromParsedCheckRuns() {
        let merge = Tender.parseCheckRuns("Unit Tests\tcompleted\tfailure\n")
        let parent = Tender.parseCheckRuns("Unit Tests\tcompleted\tsuccess\n")
        XCTAssertEqual(MainWatch.verdict(merge: merge, parent: parent), .broke(["Unit Tests"]))
    }

    func testConflictFilesAndLeftoverMarkers() {
        XCTAssertEqual(Tender.conflictFiles("a.swift\nsub/b.ts\n"), ["a.swift", "sub/b.ts"])
        XCTAssertEqual(Tender.conflictFiles(""), [])
        XCTAssertTrue(Tender.hasLeftoverMarkers("a.swift:3: leftover conflict marker\n"))
        XCTAssertFalse(Tender.hasLeftoverMarkers("a.swift:3: trailing whitespace.\n"))
    }

    func testOutsideConflictsLeavesOnlyWhatTheSessionTouchedBeside() {
        // A file the merge staged cleanly (in neither list) is not reported; an unstaged edit and an untracked file are.
        XCTAssertEqual(Tender.outsideConflicts(unstaged: "b.swift\na.swift\n", untracked: "new.txt\n",
                                               conflicts: ["a.swift"]), ["b.swift", "new.txt"])
        XCTAssertEqual(Tender.outsideConflicts(unstaged: "a.swift\n", untracked: "", conflicts: ["a.swift"]), [])
        XCTAssertEqual(Tender.outsideConflicts(unstaged: "", untracked: "", conflicts: ["a.swift"]), [])
    }

    func testRunTitlesForLandingAndBreak() {
        var run = RunState.new(id: "r", now: Date(), kind: "tend", target: "pr:acme/api#7")
        run.tendAction = "landed"
        XCTAssertEqual(RunDigest.title(for: run), "Landed #7")
        run.tendAction = "broke"
        XCTAssertEqual(RunDigest.title(for: run), "Main broke after #7")
    }
}
