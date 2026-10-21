import XCTest
@testable import ReviewRadar

final class ReviewValidatorTests: XCTestCase {
    let files: Set<String> = ["a.swift", "b.swift"]

    func draft(verdict: String = "changes", reason: String = "missing test", body: String = "Looks off.",
               comments: [DraftComment] = []) -> Draft {
        Draft(verdict: verdict, reason: reason, body: body, comments: comments)
    }

    func comment(_ path: String = "a.swift", line: Int = 3, body: String = "fix") -> DraftComment {
        DraftComment(path: path, line: line, side: nil, body: body)
    }

    func testCommentModeBuildsCommentWithVerdictLine() throws {
        let p = try ReviewValidator.validate(draft(comments: [comment()]), files: files, posting: .comment, head: "abc")
        XCTAssertEqual(p.event, "COMMENT")
        XCTAssertEqual(p.commit_id, "abc")
        XCTAssertTrue(p.body.hasPrefix("Verdict: changes\n\n"))
        XCTAssertEqual(p.comments, [PayloadComment(path: "a.swift", line: 3, side: "RIGHT", body: "fix")])
    }

    func testOwnPRsAlwaysGetACommentReview() throws {
        let p = try ReviewValidator.validate(draft(verdict: "approve"), files: files, posting: .review, head: "h", own: true)
        XCTAssertEqual(p.event, "COMMENT")
        XCTAssertTrue(p.body.hasPrefix("Verdict: approve\n\n"))
    }

    func testReviewModeMapsVerdictToEvent() throws {
        XCTAssertEqual(try ReviewValidator.validate(draft(verdict: "approve"), files: files, posting: .review, head: "h").event, "APPROVE")
        XCTAssertEqual(try ReviewValidator.validate(draft(), files: files, posting: .review, head: "h").event, "REQUEST_CHANGES")
    }

    func testRefusals() {
        func refused(_ d: Draft, _ why: String, line: UInt = #line) {
            XCTAssertThrowsError(try ReviewValidator.validate(d, files: files, posting: .comment, head: "h"), why, file: #filePath, line: line)
        }
        refused(draft(verdict: "merge"), "bad verdict")
        refused(draft(reason: String(repeating: "x", count: 61)), "reason too long")
        refused(draft(reason: "two\nlines"), "multi-line reason")
        refused(draft(body: String(repeating: "x", count: 6001)), "body too long")
        refused(draft(body: "  "), "empty body")
        refused(draft(comments: Array(repeating: comment(), count: 6)), "six comments")
        refused(draft(comments: [comment("../etc/passwd")]), "path not in PR")
        refused(draft(comments: [comment("c.swift")]), "path not in PR")
        refused(draft(comments: [comment(line: 0)]), "line zero")
        refused(draft(comments: [comment(body: String(repeating: "x", count: 1501))]), "comment too long")
        refused(draft(comments: [DraftComment(path: "a.swift", line: 1, side: "LEFT", body: "x")]), "LEFT side")
        refused(draft(body: "see ![chart](https://github.com/a/b/x.png)"), "image")
        refused(draft(body: "<img src=x>"), "img tag")
        refused(draft(body: "see <a href=x>this</a>"), "anchor tag")
        refused(draft(body: "close </div> here"), "closing tag")
        refused(draft(body: "see www.example.com"), "www autolink")
        refused(draft(body: "mail ftp://files.example"), "ftp scheme")
        refused(draft(body: "mailto:someone@example.com"), "mailto scheme")
        refused(draft(body: "[x](javascript:alert(1))"), "javascript scheme")
        refused(draft(body: "data:text/html,hi"), "data scheme")
        refused(draft(body: "<iframe src=x>"), "iframe tag")
        refused(draft(body: "read https://evil.example/x"), "non-github link")
        refused(draft(comments: [comment(body: "see http://pastebin.com/abc")]), "non-github link in comment")
        refused(draft(body: "x https://GitHub.com.evil.net/x"), "lookalike host")
    }

    func testPlainTextThatResemblesMarkupIsAllowed() {
        XCTAssertNoThrow(try ReviewValidator.validate(draft(body: "metadata: fine, a < b, and x<=y is not a tag"),
                                                      files: files, posting: .comment, head: "h"))
    }

    func testGitHubLinksAndFiveCommentsAllowed() {
        XCTAssertNoThrow(try ReviewValidator.validate(draft(body: "see https://github.com/acme/api/pull/3"),
                                                      files: files, posting: .comment, head: "h"))
        XCTAssertNoThrow(try ReviewValidator.validate(draft(comments: Array(repeating: comment(), count: 5)),
                                                      files: files, posting: .comment, head: "h"))
    }

    func testURLHostExtraction() {
        XCTAssertEqual(ReviewValidator.urlHosts(in: "a https://GitHub.com/x and (http://y.org/z) end"),
                       ["github.com", "y.org"])
    }
}
