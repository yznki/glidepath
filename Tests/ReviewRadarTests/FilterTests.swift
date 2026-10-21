import XCTest
@testable import ReviewRadar

final class FilterTests: XCTestCase {
    let limits = Limits(maxPRsPerRun: 10, maxChangedLines: 100, splitOverLines: 50)

    func pr(author: String = "alice", draft: Bool = false, bot: Bool = false,
            sha: String = "abc", add: Int = 10, del: Int = 5) -> PRInfo {
        PRInfo(n: 1, title: "t", author: author, authorIsBot: bot, isDraft: draft,
               headSha: sha, additions: add, deletions: del)
    }

    func eval(_ p: PRInfo, authors: AuthorPolicy = .collaborators, reviewed: Set<String> = [],
              collaborator: Bool = true) -> Decision {
        PRFilter.evaluate(p, me: "me", authors: authors, limits: limits,
                          reviewedHeads: reviewed, isCollaborator: { collaborator })
    }

    func testKeepsPlainCollaboratorPR() {
        XCTAssertEqual(eval(pr()), .keep)
    }

    func testSkipReasons() {
        XCTAssertEqual(eval(pr(author: "ME")), .skip("your own PR"))
        XCTAssertEqual(eval(pr(draft: true)), .skip("draft"))
        XCTAssertEqual(eval(pr(bot: true)), .skip("bot author"))
        XCTAssertEqual(eval(pr(author: "dependabot[bot]")), .skip("bot author"))
        XCTAssertEqual(eval(pr(), collaborator: false), .skip("author is not a collaborator"))
        XCTAssertEqual(eval(pr(), reviewed: ["abc"]), .skip("already reviewed at this head"))
        XCTAssertEqual(eval(pr(add: 90, del: 20)), .skip("too large (110 changed lines)"))
    }

    func testReviewedAtOtherHeadIsKept() {
        XCTAssertEqual(eval(pr(sha: "new"), reviewed: ["old"]), .keep)
    }

    func testAuthorPolicies() {
        XCTAssertEqual(eval(pr(), authors: .anyone, collaborator: false), .keep)
        XCTAssertEqual(eval(pr(author: "bob"), authors: .logins(["alice"])), .skip("author not in authors list"))
        XCTAssertEqual(eval(pr(author: "Alice"), authors: .logins(["alice"])), .keep)
    }

    func testCollaboratorCheckOnlyRunsWhenNeeded() {
        var called = false
        _ = PRFilter.evaluate(pr(author: "me"), me: "me", authors: .collaborators, limits: limits,
                              reviewedHeads: [], isCollaborator: { called = true; return true })
        XCTAssertFalse(called)
    }
}
