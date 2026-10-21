import XCTest
@testable import Glidepath

final class DashboardTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func hostileRun() throws -> RunState {
        var run = RunState.new(id: "run-1", now: now)
        try run.setPR(repo: "acme/api", n: 9, stage: nil, author: "\"><img onerror=alert(1)>",
                      title: "<script>alert(1)</script>", verdict: .changes, reason: "x & <b>y</b>")
        run.finish(at: now.addingTimeInterval(600), error: nil)
        return run
    }

    func render(_ runs: [RunState], drafts: [Drafts.Found] = []) -> String {
        DashboardPage.render(runs: runs, drafts: drafts, header: HeaderCopy.make(.noSweeps(next: nil, repos: 1), now: now), now: now)
    }

    func testEveryStringFromGitHubIsEscaped() throws {
        let html = render([try hostileRun()])
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains("<b>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&quot;&gt;&lt;img onerror=alert(1)&gt;"))
        XCTAssertTrue(html.contains("x &amp; &lt;b&gt;y&lt;/b&gt;"))
    }

    func testDraftBodyIsEscapedAndCarriesThePostCommand() {
        let draft = DraftFile(slug: "acme/api", n: 9, head: "h", event: "REQUEST_CHANGES",
                              body: "</pre><script>x</script>", comments: [], created: now)
        let html = render([], drafts: [Drafts.Found(runId: "r", path: "", draft: draft)])
        XCTAssertFalse(html.contains("<script"))
        XCTAssertTrue(html.contains("&lt;/pre&gt;&lt;script&gt;x&lt;/script&gt;"))
        XCTAssertTrue(html.contains("glidepath drafts post acme/api 9"))
    }

    func testPagePlansNoScriptAndCarriesTheCSP() throws {
        let html = render([try hostileRun()])
        XCTAssertTrue(html.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">"))
        XCTAssertFalse(html.lowercased().contains("<script"))
        XCTAssertTrue(html.contains("href=\"https://github.com/acme/api/pull/9\""))
    }

    func testAQuoteWithACombiningMarkIsStillEscaped() {
        XCTAssertEqual(DashboardPage.esc("\"\u{0301}<"), "&quot;\u{0301}&lt;")
        XCTAssertEqual(DashboardPage.esc("'\u{0301}"), "&#39;\u{0301}")
    }
}
