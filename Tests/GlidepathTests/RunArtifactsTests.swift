import XCTest
@testable import Glidepath

/// The flight recorder's reading of a PR's scratch folder: the loader, the checker's delta, the blast summary and the
/// owner's notes from the run log.
final class RunArtifactsTests: XCTestCase {
    private var root = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "gp-artifacts-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ text: String, _ name: String, in folder: String) throws {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try text.write(toFile: folder + "/" + name, atomically: true, encoding: .utf8)
    }

    private func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func draft(_ verdict: String, _ comments: [(String, Int, String)], body: String = "Body.") -> String {
        json([
            "verdict": verdict, "reason": "reason", "body": body,
            "comments": comments.map { ["path": $0.0, "line": $0.1, "body": $0.2] },
        ])
    }

    private func comment(_ path: String, _ line: Int) -> RunArtifacts.Comment {
        RunArtifacts.Comment(path: path, line: line, body: "\(path):\(line)")
    }

    private func review(_ verdict: Verdict?, _ comments: [(String, Int)], body: String = "Body.") -> RunArtifacts.Review {
        RunArtifacts.Review(verdict: verdict, reason: nil, body: body, comments: comments.map { comment($0.0, $0.1) })
    }

    func testLoadsEveryFileInThePRFolder() throws {
        let pr = root + "/run/acme-api/7"
        try write(json(["files": [["path": "a"], ["path": "b"], ["path": "c"]], "additions": 10, "deletions": 2,
                        "headSha": "abc1234", "baseRef": "main"]), "pr.json", in: pr)
        try write(json(["reviews": [["user": "x"]], "review_comments": [["path": "a"], ["path": "b"]],
                        "issue_comments": []]), "threads.json", in: pr)
        try write(draft("changes", [("a.swift", 4, "one")]), "draft-a.json", in: pr)
        try write(draft("approve", [("b.swift", 9, "two")]), "draft-b.json", in: pr)
        try write(draft("changes", [("a.swift", 4, "one")]), "final.json", in: pr)
        try write("Callers from grep, partial.\n- foo -> bar (x.swift:3)", "blast.md", in: pr)
        try write("- Gap one.\n- Gap two.", "notes.md", in: pr)
        try write("", "diff.patch", in: pr)
        try write("", "diff-1.patch", in: pr)
        try write("", "diff-2.patch", in: pr)

        let a = RunArtifacts.load(folder: pr)
        XCTAssertEqual(a.folder, pr)
        XCTAssertEqual(a.fileCount, 3)
        XCTAssertEqual(a.additions, 10)
        XCTAssertEqual(a.deletions, 2)
        XCTAssertEqual(a.headSha, "abc1234")
        XCTAssertEqual(a.baseRef, "main")
        XCTAssertEqual(a.commentCount, 3)
        XCTAssertEqual(a.drafts.count, 2)
        XCTAssertEqual(a.draft?.verdict, .changes, "changes wins when any draft says changes")
        XCTAssertEqual(a.draft?.comments.count, 2)
        XCTAssertEqual(a.final?.verdict, .changes)
        XCTAssertEqual(a.blast?.hasPrefix("Callers from grep"), true)
        XCTAssertEqual(a.notes, ["Gap one.", "Gap two."])
        XCTAssertEqual(a.diffParts, 2, "diff.patch is the whole diff, not a part")
    }

    func testMissingFolderIsEmpty() {
        let empty = RunArtifacts.load(folder: root + "/does-not-exist")
        XCTAssertEqual(empty, RunArtifacts())
        XCTAssertNil(empty.folder)
        XCTAssertNil(empty.commentCount)
    }

    func testFolderPathMatchesTheRunnersScratchLayout() {
        let paths = Paths(home: "/h", env: [:])
        XCTAssertEqual(RunArtifacts.folder(paths, runId: "r1", slug: "acme/api", n: 7),
                       "/h/.local/state/glidepath/scratch/r1/acme-api/7")
    }

    func testCheckerDeltaKeysFindingsByPathAndLine() {
        let drafts = [review(.changes, [("a.swift", 1), ("a.swift", 2), ("b.swift", 3)], body: "First draft.")]
        let final = review(.approve, [("a.swift", 1), ("c.swift", 4)], body: "Tighter.")
        let delta = CheckerDelta.compute(drafts: drafts, final: final)
        XCTAssertEqual(delta.kept.map { "\($0.path):\($0.line)" }, ["a.swift:1"])
        XCTAssertEqual(delta.added.map { "\($0.path):\($0.line)" }, ["c.swift:4"])
        XCTAssertEqual(delta.dropped.map { "\($0.path):\($0.line)" }, ["a.swift:2", "b.swift:3"])
        XCTAssertTrue(delta.bodyChanged)
        XCTAssertEqual(delta.verdictChanged?.from, .changes)
        XCTAssertEqual(delta.verdictChanged?.to, .approve)
    }

    func testCheckerDeltaWithoutChangesIsQuiet() {
        let draft = review(.changes, [("a.swift", 1)], body: "Same.")
        let delta = CheckerDelta.compute(drafts: [draft], final: draft)
        XCTAssertTrue(delta.added.isEmpty)
        XCTAssertTrue(delta.dropped.isEmpty)
        XCTAssertFalse(delta.bodyChanged)
        XCTAssertNil(delta.verdictChanged)
    }

    func testBlastChips() {
        let gitnexus = RunArtifacts.blastSummary("Callers from GitNexus, 3 found.\n- a -> b (x.swift:1), depth 1, low")
        XCTAssertEqual(gitnexus.chip, "GitNexus")
        XCTAssertFalse(gitnexus.partial)
        XCTAssertEqual(gitnexus.bullets, ["a -> b (x.swift:1), depth 1, low"])

        let grep = RunArtifacts.blastSummary("GitNexus not available; grep only.\n- foo")
        XCTAssertEqual(grep.chip, "grep only · partial")
        XCTAssertTrue(grep.partial)

        let notRun = RunArtifacts.blastSummary("NOT COMPLETE: no diff to read.")
        XCTAssertEqual(notRun.chip, "not run")
        XCTAssertTrue(notRun.bullets.isEmpty)
    }

    func testBlastBulletsStopAtTwelve() {
        let text = (1...15).map { "- caller \($0)" }.joined(separator: "\n")
        let summary = RunArtifacts.blastSummary(text)
        XCTAssertEqual(summary.bullets.count, 12)
        XCTAssertEqual(summary.bullets.first, "caller 1")
    }

    func testLogNotesOnlyWhenTheRunReviewedOnePR() throws {
        let repo = root + "/run/acme-api"
        let log = "review output\nNotes for the owner\n- Only this PR.\n- Could not check the routes.\n\ndone"
        try write(log, "claude.log", in: repo)

        XCTAssertEqual(RunArtifacts.logNotes(folder: repo + "/7"), [])  // no PR folder yet
        try FileManager.default.createDirectory(atPath: repo + "/7", withIntermediateDirectories: true)
        XCTAssertEqual(RunArtifacts.logNotes(folder: repo + "/7"), ["Only this PR.", "Could not check the routes."])

        try FileManager.default.createDirectory(atPath: repo + "/8", withIntermediateDirectories: true)
        XCTAssertEqual(RunArtifacts.logNotes(folder: repo + "/7"), [], "a run with two PRs has no per-PR notes")
    }
}
