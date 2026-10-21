import XCTest
@testable import ReviewRadar

final class FilterTests: XCTestCase {
    let limits = Limits(maxPRsPerRun: 10, maxChangedLines: 100, splitOverLines: 50)

    func pr(author: String = "alice", draft: Bool = false, bot: Bool = false,
            sha: String = "abc", add: Int = 10, del: Int = 5) -> PRInfo {
        PRInfo(n: 1, title: "t", author: author, authorIsBot: bot, isDraft: draft,
               headSha: sha, additions: add, deletions: del)
    }

    var includeOwn = false

    func eval(_ p: PRInfo, authors: AuthorPolicy = .collaborators, reviewed: Set<String>? = [],
              collaborator: Bool? = true) -> Decision {
        PRFilter.evaluate(p, me: "me", includeOwn: includeOwn, authors: authors, limits: limits,
                          isCollaborator: { collaborator }, reviewedHeads: { reviewed })
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
        XCTAssertEqual(eval(pr(), collaborator: nil),
                       .skip("cannot read collaborator permission (needs push access); list authors explicitly"))
        XCTAssertEqual(eval(pr(), reviewed: nil), .skip("could not read existing reviews"))
        XCTAssertEqual(eval(pr(), reviewed: ["abc"]), .skip("already reviewed at this head"))
        XCTAssertEqual(eval(pr(add: 90, del: 20)), .skip("too large (110 changed lines)"))
    }

    func testOwnPRsOnlyWhenIncluded() {
        XCTAssertEqual(eval(pr(author: "me")), .skip("your own PR"))
        includeOwn = true
        defer { includeOwn = false }
        XCTAssertEqual(eval(pr(author: "me")), .keep)
        XCTAssertEqual(eval(pr(author: "me", draft: true)), .skip("draft"), "other rules still apply to own PRs")
    }

    func testReviewedAtOtherHeadIsKept() {
        XCTAssertEqual(eval(pr(sha: "new"), reviewed: ["old"]), .keep)
    }

    func testAuthorPolicies() {
        XCTAssertEqual(eval(pr(), authors: .anyone, collaborator: false), .keep)
        XCTAssertEqual(eval(pr(author: "bob"), authors: .logins(["alice"])), .skip("author not in authors list"))
        XCTAssertEqual(eval(pr(author: "dependabot[bot]", bot: true), authors: .logins(["dependabot[bot]"])), .keep)
        XCTAssertEqual(eval(pr(author: "Alice"), authors: .logins(["alice"])), .keep)
    }

    func testAPICallsOnlyForPRsThatGetThatFar() {
        var lookups = 0
        _ = PRFilter.evaluate(pr(add: 90, del: 20), me: "me", authors: .collaborators, limits: limits,
                              isCollaborator: { lookups += 1; return true }, reviewedHeads: { lookups += 1; return [] })
        XCTAssertEqual(lookups, 0, "size is a cheap check and must run before any API call")
        _ = PRFilter.evaluate(pr(), me: "me", authors: .collaborators, limits: limits,
                              isCollaborator: { lookups += 1; return true }, reviewedHeads: { lookups += 1; return [] })
        XCTAssertEqual(lookups, 2)
    }
}
