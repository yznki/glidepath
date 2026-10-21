import XCTest
@testable import Glidepath

final class DraftTests: XCTestCase {
    var home: String!
    var paths: Paths!
    let files: Set<String> = ["a.swift", "infra/main.tf"]
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("rr-drafts-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        paths = Paths(home: home, env: ["GLIDEPATH_STATE_DIR": home + "/state"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    func draft(_ n: Int = 7, event: String = "REQUEST_CHANGES", body: String = "Looks off.",
               comments: [PayloadComment] = [], created: Date? = nil, stale: Bool? = nil) -> DraftFile {
        DraftFile(slug: "acme/api", n: n, head: "abc", event: event, body: body, comments: comments,
                  created: created ?? now, stale: stale)
    }

    func payload(event: String = "COMMENT", body: String = "Looks off.", comments: [PayloadComment] = []) -> ReviewPayload {
        ReviewPayload(commit_id: "abc", event: event, body: body, comments: comments)
    }

    func testDraftModeBuildsTheReviewEvent() throws {
        let d = Draft(verdict: "approve", reason: "fine", body: "Ship it.", comments: [])
        XCTAssertEqual(try ReviewValidator.validate(d, files: files, posting: .draft, head: "h").event, "APPROVE")
        XCTAssertEqual(try ReviewValidator.validate(d, files: files, posting: .draft, head: "h", own: true).event, "COMMENT")
    }

    func testNewestOpenDraftWinsAndStaleDraftsAreHidden() throws {
        try Drafts.write(draft(created: now), runId: "run-old", paths)
        try Drafts.write(draft(created: now.addingTimeInterval(60)), runId: "run-new", paths)
        XCTAssertEqual(Drafts.newest(paths, slug: "acme/api", n: 7)?.runId, "run-new")
        try Drafts.write(draft(created: now.addingTimeInterval(60), stale: true), runId: "run-new", paths)
        XCTAssertEqual(Drafts.newest(paths, slug: "acme/api", n: 7)?.runId, "run-old", "a stale draft is not offered")
        XCTAssertEqual(Drafts.all(paths, includeStale: true).count, 2)
        XCTAssertNil(Drafts.newest(paths, slug: "acme/api", n: 8))
    }

    func testTamperedDraftFileIsRefusedBeforePosting() {
        func refused(_ p: ReviewPayload, own: Bool = false, _ why: String, line: UInt = #line) {
            XCTAssertThrowsError(try ReviewValidator.checkPayload(p, files: files, own: own), why, file: #filePath, line: line)
        }
        refused(payload(event: "MERGE"), "unknown event")
        refused(payload(event: "APPROVE"), own: true, "own PR with a real review event")
        refused(payload(body: "<script>alert(1)</script>"), "markup in the body")
        refused(payload(body: "![x](https://github.com/a/b.png)"), "image in the body")
        refused(payload(body: String(repeating: "x", count: ReviewValidator.maxBody + ReviewValidator.verdictLineRoom + 1)), "body too long")
        refused(payload(comments: [PayloadComment(path: "../secret", line: 1, side: "RIGHT", body: "x")]), "path outside the PR")
        refused(payload(comments: [PayloadComment(path: "a.swift", line: 0, side: "RIGHT", body: "x")]), "line zero")
        refused(payload(comments: [PayloadComment(path: "a.swift", line: 1, side: "LEFT", body: "x")]), "left side")
        refused(payload(comments: Array(repeating: PayloadComment(path: "a.swift", line: 1, side: "RIGHT", body: "x"), count: 6)),
                "six comments")
        XCTAssertNoThrow(try ReviewValidator.checkPayload(payload(event: "COMMENT", body: "Verdict: changes\n\nFine."), files: files, own: true))
    }

    func testDiscardRemovesTheDraftAndClearsTheRow() throws {
        var run = RunState.new(id: "run-1", now: now)
        try run.setPR(repo: "acme/api", n: 7, stage: nil, author: "ines", title: "T", verdict: .changes, reason: "x")
        run.setDraft(repo: "acme/api", n: 7, draft: true, posted: nil)
        try RunStore(paths: paths).save(run)
        try Drafts.write(draft(), runId: "run-1", paths)

        XCTAssertEqual(try DraftCommands.discard(paths, "acme/api", 7), "discarded the draft for acme/api #7")
        XCTAssertNil(Drafts.newest(paths, slug: "acme/api", n: 7))
        let row = try XCTUnwrap(try RunStore(paths: paths).load("run-1").repos.first?.prs.first)
        XCTAssertEqual(row.draft, false)
        XCTAssertEqual(row.verdict, .changes, "the verdict stays")
    }

    func testMovedHeadMessageNamesThePRAndTheNextSweep() {
        XCTAssertEqual(DraftCommands.movedMessage(7), "PR #7 changed since this draft; the next sweep reviews it again")
    }

    func testFlagPathsMatchByPrefix() {
        XCTAssertEqual(FlagPaths.matches(["infra/main.tf", "infrastructure.md", "src/a.swift"], prefixes: ["infra/"]),
                       ["infra/main.tf"])
        XCTAssertEqual(FlagPaths.matches(["x"], prefixes: []), [])
    }

    func testFlagNoteFormatting() {
        let note = "Needs a devops code-owner approval."
        XCTAssertNil(FlagPaths.note(note, matches: []))
        XCTAssertEqual(FlagPaths.note(note, matches: ["infra/a.tf"]),
                       "**Note:** Needs a devops code-owner approval. (infra/a.tf)")
        XCTAssertEqual(FlagPaths.note(note, matches: ["infra/a", "infra/b", "infra/c"]),
                       "**Note:** Needs a devops code-owner approval. (infra/a, infra/b, infra/c)")
        XCTAssertEqual(FlagPaths.note(note, matches: ["infra/a", "infra/b", "infra/c", "infra/d"]),
                       "**Note:** Needs a devops code-owner approval. (infra/a, infra/b, infra/c, +1 more)")
    }

    func testFlagNoteIsValidatedWithTheBody() {
        let d = Draft(verdict: "changes", reason: "x", body: "Fix it.", comments: [])
        XCTAssertThrowsError(try ReviewValidator.validate(d, files: files, posting: .review, head: "h",
                                                          note: "**Note:** see <b>this</b>"))
    }
}
