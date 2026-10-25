import XCTest
@testable import Glidepath

final class ReviewCommandTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func info(_ n: Int, lines: Int, draft: Bool = false, author: String = "ines") -> PRInfo {
        PRInfo(n: n, title: "T", author: author, authorIsBot: false, isDraft: draft, headSha: "h",
               additions: lines, deletions: 0)
    }

    func testByHandKeepsPRsThatASweepSkips() {
        let base = Limits(maxPRsPerRun: 10, maxChangedLines: 3000, splitOverLines: 1500)
        // By hand, the collaborator lookup never runs.
        let noLookup: () -> Bool? = { XCTFail("isCollaborator is not read by hand"); return nil }
        func byHand(_ pr: PRInfo, authors: AuthorPolicy = .anyone) -> Decision {
            PRFilter.evaluate(pr, me: "me", byHand: true, authors: authors, limits: base,
                              isCollaborator: noLookup, reviewedHeads: { [] })
        }
        func sweep(_ pr: PRInfo, authors: AuthorPolicy = .anyone) -> Decision {
            PRFilter.evaluate(pr, me: "me", authors: authors, limits: base,
                              isCollaborator: { false }, reviewedHeads: { [] })
        }
        XCTAssertEqual(sweep(info(1219, lines: 12_480)), .skip("too large (12480 changed lines)"))
        XCTAssertEqual(byHand(info(1219, lines: 12_480)), .keep, "the size limit does not apply by hand")
        XCTAssertEqual(byHand(info(2, lines: 10, draft: true)), .keep, "a draft is reviewed by hand")
        XCTAssertEqual(byHand(info(3, lines: 10, author: "renovate[bot]")), .keep, "a bot is reviewed by hand")
        XCTAssertEqual(sweep(info(3, lines: 10, author: "renovate[bot]")), .skip("bot author"))
        XCTAssertEqual(byHand(info(4, lines: 10), authors: .collaborators), .keep, "a non-collaborator is reviewed by hand")
        XCTAssertEqual(sweep(info(4, lines: 10), authors: .collaborators), .skip("author is not a collaborator"))
        XCTAssertEqual(byHand(info(5, lines: 10, author: "ines"), authors: .logins(["x"])), .keep,
                       "an author outside the list is reviewed by hand")
        XCTAssertEqual(sweep(info(5, lines: 10, author: "ines"), authors: .logins(["x"])), .skip("author not in authors list"))
    }

    func testByHandStillSkipsOwnReviewedAndHeldPRs() {
        let base = Limits()
        func byHand(_ pr: PRInfo, draftHeads: Set<String> = [], reviewed: Set<String> = []) -> Decision {
            PRFilter.evaluate(pr, me: "me", byHand: true, authors: .anyone, limits: base, draftHeads: draftHeads,
                              isCollaborator: { true }, reviewedHeads: { reviewed })
        }
        XCTAssertEqual(byHand(info(1, lines: 100, author: "me")), .skip("your own PR"))
        XCTAssertEqual(byHand(info(2, lines: 100), reviewed: ["h"]), .skip("already reviewed at this head"))
        XCTAssertEqual(byHand(info(3, lines: 100), draftHeads: ["h"]), .skip("draft waiting"))
    }

    func testIncludeOwnIsForcedOnlyForANamedPR() {
        let off = RepoConfig(slug: "acme/api", clone: "/fake")
        var on = off
        on.includeOwn = true
        let pr = ReviewTarget.prs([PRRef(slug: "acme/api", n: 2)])
        XCTAssertTrue(Runner.includeOwn(off, target: pr), "a named PR is reviewed even when it is yours")
        XCTAssertFalse(Runner.includeOwn(off, target: .author("me")), "author mode skips your own PRs")
        XCTAssertFalse(Runner.includeOwn(off, target: nil), "a sweep skips your own PRs")
        XCTAssertTrue(Runner.includeOwn(on, target: pr))
        XCTAssertTrue(Runner.includeOwn(on, target: .author("me")))
        XCTAssertTrue(Runner.includeOwn(on, target: nil))
    }

    func testParsePRsAcceptsNumbersAndLinks() {
        func refs(_ tokens: [String], defaultRepo: String? = nil) -> [String]? {
            ReviewTarget.parsePRs(tokens, defaultRepo: defaultRepo)?.map { "\($0.slug)#\($0.n)" }
        }
        XCTAssertEqual(refs(["acme/api", "12"]), ["acme/api#12"])
        XCTAssertEqual(refs(["acme/api", "12", "15", "#18"]), ["acme/api#12", "acme/api#15", "acme/api#18"])
        XCTAssertEqual(refs(["acme/api", "1", "acme/web", "2"]), ["acme/api#1", "acme/web#2"])
        XCTAssertEqual(refs(["https://github.com/acme/api/pull/1", "https://github.com/acme/web/pull/2"]),
                       ["acme/api#1", "acme/web#2"])
        XCTAssertEqual(refs(["acme/api", "1", "https://github.com/acme/web/pull/2", "3"]),
                       ["acme/api#1", "acme/web#2", "acme/api#3"])
        XCTAssertEqual(refs(["acme/api", "1", "1", "acme/API", "1", "2"]), ["acme/api#1", "acme/API#2"])
        XCTAssertEqual(refs(["https://github.com/acme/api/pull/12"]), ["acme/api#12"])
        XCTAssertEqual(refs(["https://github.com/acme/api/pull/12/files"]), ["acme/api#12"])
        XCTAssertEqual(refs(["https://www.github.com/acme/api/pull/12#discussion_r1"]), ["acme/api#12"])
        XCTAssertEqual(refs(["12", "15"], defaultRepo: "acme/api"), ["acme/api#12", "acme/api#15"])
        XCTAssertNil(refs(["12"]))
        XCTAssertNil(refs(["acme/api"]))
        XCTAssertNil(refs(["acme/api", "0"]))
        XCTAssertNil(refs(["acme/api", "012"]))
        XCTAssertNil(refs(["acme/api", "x"]))
        XCTAssertNil(refs(["acme/api", "1", "acme/web"]))
        XCTAssertNil(refs(["https://gitlab.com/acme/api/pull/12"]))
        XCTAssertNil(refs(["https://github.com/acme/api/issues/12"]))
        XCTAssertNil(refs([]))
    }

    func testParseReadsEachFormAndRefusesTheRest() throws {
        let author = try XCTUnwrap(ReviewCommand.parse(["--author", "ines"]))
        XCTAssertEqual(author.target, .author("ines"))
        XCTAssertNil(author.repo)
        XCTAssertFalse(author.again)
        let narrow = try XCTUnwrap(ReviewCommand.parse(["--author", "ines", "--repo", "acme/api", "--again"]))
        XCTAssertEqual(narrow.target, .author("ines"))
        XCTAssertEqual(narrow.repo, "acme/api")
        XCTAssertTrue(narrow.again)
        let number = try XCTUnwrap(ReviewCommand.parse(["acme/api", "3", "--dry-run"]))
        XCTAssertEqual(number.target, .prs([PRRef(slug: "acme/api", n: 3)]))
        XCTAssertTrue(number.dryRun)
        for args in [["--author"], ["--author", "bad login"], ["--author", "ines", "acme/api", "1"],
                     ["acme/api", "1", "--repo", "acme/api"], ["acme/api", "1", "--force"]] {
            XCTAssertNil(ReviewCommand.parse(args), "\(args) is refused")
        }
    }

    func testIncludesIgnoresCaseForSlugsAndLogins() {
        XCTAssertTrue(ReviewTarget.author("Ines").includes(slug: "acme/api", n: 1, author: "ines"))
        XCTAssertFalse(ReviewTarget.author("ines").includes(slug: "acme/api", n: 1, author: nil))
        XCTAssertTrue(ReviewTarget.prs([PRRef(slug: "Acme/API", n: 4)]).includes(slug: "acme/api", n: 4, author: nil))
        XCTAssertFalse(ReviewTarget.prs([PRRef(slug: "acme/api", n: 4)]).includes(slug: "acme/api", n: 5, author: "ines"))
        XCTAssertTrue(ReviewTarget.prs([PRRef(slug: "acme/api", n: 4), PRRef(slug: "acme/web", n: 2)])
            .includes(slug: "ACME/web", n: 2, author: nil))
    }

    func testByHandPRsRoundTripThroughTheArguments() throws {
        let target = ReviewTarget.prs([PRRef(slug: "acme/api", n: 1), PRRef(slug: "acme/api", n: 3),
                                       PRRef(slug: "acme/web", n: 2)])
        XCTAssertEqual(target.arguments, ["review", "acme/api", "1", "3", "acme/web", "2"])
        let parsed = try XCTUnwrap(ReviewCommand.parse(Array(target.arguments.dropFirst())))
        XCTAssertEqual(parsed.target, target)
    }

    func testIncludeOwnIsForcedForNamedPRs() {
        let off = RepoConfig(slug: "acme/api", clone: "/fake")
        XCTAssertTrue(Runner.includeOwn(off, target: .prs([PRRef(slug: "acme/api", n: 1), PRRef(slug: "acme/web", n: 2)])))
    }

    func testHeldRunLockRefusesAReview() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rr-lock-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let held = try XCTUnwrap(try RunLock.acquire(path))
        XCTAssertNil(try RunLock.acquire(path), "a second review cannot take the lock")
        withExtendedLifetime(held) {}
    }

    func testReviewWarningWithAndWithoutAnEstimate() throws {
        let plain = Presentation.reviewWarning(changedLines: 12_480, limit: 8_000, last: nil)
        XCTAssertEqual(plain, "It changes 12,480 lines, over your 8,000 limit. "
                       + "It will be split across several reviewers and may use a lot of tokens.")

        var last = RunState.new(id: "last", now: now)
        try last.setPR(repo: "acme/api", n: 1, stage: nil, author: nil, title: nil, verdict: .approve, reason: nil)
        try last.setPR(repo: "acme/api", n: 2, stage: nil, author: nil, title: nil, verdict: .changes, reason: "x")
        last.setSize(repo: "acme/api", n: 1, changedLines: 1000, skippedForSize: false)
        last.setSize(repo: "acme/api", n: 2, changedLines: 3000, skippedForSize: false)
        last.tokens = 733_000
        last.finish(at: now, error: nil)
        XCTAssertEqual(Presentation.reviewEstimate(last, changedLines: 4000), 366_500 * 4000 / 2000)
        let with = Presentation.reviewWarning(changedLines: 4000, limit: 3000, last: last)
        XCTAssertTrue(with.contains("(the last run used 733k for 2 PRs)."), with)
        XCTAssertTrue(with.hasSuffix("This PR is about 733k tokens, going by the last run."), with)
    }

    func testEstimateNeedsSizesFromTheLastRun() {
        var old = RunState.new(id: "old", now: now)
        old.tokens = 100
        old.finish(at: now, error: nil)
        XCTAssertNil(Presentation.reviewEstimate(old, changedLines: 10), "no sizes recorded, no estimate")
    }

    func testTooLargeLineCopy() {
        XCTAssertEqual(Presentation.sizeText(12_480), "Too large · 12,480 lines")
    }
}
