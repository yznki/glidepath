import XCTest
@testable import Glidepath

final class ReviewCommandTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func info(_ n: Int, lines: Int, draft: Bool = false, author: String = "ines") -> PRInfo {
        PRInfo(n: n, title: "T", author: author, authorIsBot: false, isDraft: draft, headSha: "h",
               additions: lines, deletions: 0)
    }

    func testOnlyTheNamedPRGetsTheSizeOverride() {
        let base = Limits(maxPRsPerRun: 10, maxChangedLines: 3000, splitOverLines: 1500)
        let big = info(1219, lines: 12_480)
        func decide(_ pr: PRInfo, reviewing target: Int?) -> Decision {
            PRFilter.evaluate(pr, me: "me", authors: .anyone,
                              limits: Runner.limits(base, for: pr.n, reviewing: target),
                              isCollaborator: { true }, reviewedHeads: { [] })
        }
        XCTAssertEqual(decide(big, reviewing: nil), .skip("too large (12480 changed lines)"))
        XCTAssertEqual(decide(big, reviewing: 1219), .keep)
        XCTAssertEqual(decide(info(1220, lines: 12_480), reviewing: 1219), .skip("too large (12480 changed lines)"),
                       "another PR stays skipped")
    }

    func testOtherFiltersStillApplyToTheNamedPR() {
        let base = Limits()
        let draft = info(1219, lines: 12_480, draft: true)
        XCTAssertEqual(PRFilter.evaluate(draft, me: "me", authors: .anyone,
                                         limits: Runner.limits(base, for: 1219, reviewing: 1219),
                                         isCollaborator: { true }, reviewedHeads: { [] }), .skip("draft"))
        let mine = info(1220, lines: 100, author: "me")
        XCTAssertEqual(PRFilter.evaluate(mine, me: "me", authors: .anyone, limits: base,
                                         isCollaborator: { true }, reviewedHeads: { [] }), .skip("your own PR"))
        XCTAssertEqual(PRFilter.evaluate(info(1219, lines: 12_480), me: "me", authors: .anyone,
                                         limits: Runner.limits(base, for: 1219, reviewing: 1219),
                                         isCollaborator: { true }, reviewedHeads: { ["h"] }),
                       .skip("already reviewed at this head"))
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
