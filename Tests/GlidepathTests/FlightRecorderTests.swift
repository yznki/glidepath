import XCTest
@testable import Glidepath

/// The flight recorder's stage rules (`ApproachState`), its text helpers and the header's duration.
final class FlightRecorderTests: XCTestCase {
    private let posted = Date(timeIntervalSince1970: 1_700_000_000)

    private func row(verdict: Verdict? = nil, draft: Bool = false, postedAt: Date? = nil, stage: Stage = .post,
                     reason: String? = nil, skipReason: String? = nil, tokens: Int = 400_000) -> ReviewRow {
        ReviewRow(runId: "r1", repo: "acme/api", number: 7, author: "ana", title: "Title", reason: reason,
                  verdict: verdict, draft: draft, skipReason: skipReason, changedLines: 120, head: "abc1234",
                  flagged: false, tokens: tokens, duration: 192, postedAt: postedAt, stage: stage)
    }

    /// Artifacts as if the folder was read: loaded, with a folder.
    private var loaded: RunArtifacts {
        var a = RunArtifacts()
        a.folder = "/scratch/r1/acme-api/7"
        return a
    }

    func testFilterSkipIsHiddenOnceLoaded() {
        let filter = row(verdict: .skipped, stage: .gather, reason: nil, tokens: 0)
        let state = ApproachState(row: filter, artifacts: RunArtifacts())
        XCTAssertTrue(state.filtered)
        XCTAssertFalse(state.sessionSkip)
        XCTAssertFalse(state.reviewAgainOffered)

        XCTAssertFalse(ApproachState(row: filter, artifacts: nil).filtered, "the approach stays until the artifacts load")
    }

    func testSessionSkipKeepsTheApproachAndOffersReviewAgain() {
        let session = row(verdict: .skipped, stage: .review, reason: "Session skipped it: generated code", tokens: 9_000)
        let state = ApproachState(row: session, artifacts: loaded)
        XCTAssertFalse(state.filtered)
        XCTAssertTrue(state.sessionSkip)
        XCTAssertEqual(state.reached, 2)
        XCTAssertEqual(state.landWord, "Skipped")
        XCTAssertEqual(state.landSub, "Session skipped it: generated c…")
        XCTAssertTrue(state.reviewAgainOffered)
        XCTAssertFalse(ApproachState(row: session, artifacts: nil).reviewAgainOffered, "review again waits for the load")
    }

    func testNoResultOffersReviewAgainAndStopsBeforeLand() {
        let none = row(verdict: nil, stage: .check, tokens: 58_000)
        let state = ApproachState(row: none, artifacts: loaded)
        XCTAssertFalse(state.landed)
        XCTAssertEqual(state.reached, 3)
        XCTAssertEqual(state.landWord, "No result")
        XCTAssertEqual(state.landSub, "Nothing posted")
        XCTAssertTrue(state.reviewAgainOffered)
    }

    func testHeldDraftLandsAndOffersNoReviewAgain() {
        let draft = row(verdict: .changes, draft: true, stage: .post)
        let state = ApproachState(row: draft, artifacts: loaded)
        XCTAssertTrue(state.landed)
        XCTAssertEqual(state.reached, 4)
        XCTAssertEqual(state.landWord, "Held as draft")
        XCTAssertFalse(state.reviewAgainOffered)
    }

    func testPostedApproveLands() {
        let approve = row(verdict: .approve, postedAt: posted)
        let state = ApproachState(row: approve, artifacts: loaded)
        XCTAssertTrue(state.landed)
        XCTAssertFalse(state.notPosted)
        XCTAssertEqual(state.reached, 4)
        XCTAssertEqual(state.landWord, "Posted")
        XCTAssertFalse(state.reviewAgainOffered)
    }

    func testPostedChangesLands() {
        let changes = row(verdict: .changes, postedAt: posted)
        let state = ApproachState(row: changes, artifacts: loaded)
        XCTAssertTrue(state.landed)
        XCTAssertEqual(state.landWord, "Posted")
        XCTAssertNotNil(state.landSub)
    }

    func testCommentOnlyPostLandsLikeAnyPost() {
        // The text record says COMMENT; the approach reads only the row, so a comment-only post lands the same way.
        let comment = row(verdict: .changes, postedAt: posted)
        XCTAssertEqual(ApproachState(row: comment, artifacts: loaded).landWord, "Posted")
    }

    func testTooLargeStaysAtGather() {
        let big = row(verdict: nil, stage: .gather, skipReason: "size", tokens: 0)
        let state = ApproachState(row: big, artifacts: RunArtifacts())
        XCTAssertFalse(state.filtered, "a too-large skip is not a filter skip")
        XCTAssertFalse(state.sessionSkip)
        XCTAssertEqual(state.reached, 1)
        XCTAssertFalse(state.reviewAgainOffered, "too-large rows offer Review anyway, not Review again")
    }

    func testVerdictWithoutPostingIsNotPostedAndOffersReviewAgain() {
        let discarded = row(verdict: .changes, stage: .post)
        let state = ApproachState(row: discarded, artifacts: loaded)
        XCTAssertFalse(state.landed)
        XCTAssertTrue(state.notPosted)
        XCTAssertEqual(state.reached, 3, "the run stops after the last reached stage, before Land")
        XCTAssertEqual(state.landWord, "Not posted")
        XCTAssertEqual(state.landSub, "Discarded, stale or dry run")
        XCTAssertTrue(state.reviewAgainOffered)
        XCTAssertTrue(state.stopped)
    }

    func testPrunedScratchStillShowsTheRowsLanding() {
        let pruned = row(verdict: .approve, postedAt: posted)
        let state = ApproachState(row: pruned, artifacts: RunArtifacts())
        XCTAssertTrue(state.landed)
        XCTAssertFalse(state.filtered)
        XCTAssertEqual(state.landWord, "Posted")
    }

    func testLandSubIsCutSoItStaysInTheProfile() {
        let long = row(verdict: .skipped, stage: .review, reason: String(repeating: "word ", count: 30), tokens: 5)
        let sub = ApproachState(row: long, artifacts: loaded).landSub ?? ""
        XCTAssertLessThanOrEqual(sub.count, 32)
        XCTAssertTrue(sub.hasSuffix("…"))
    }

    func testReadoutsFollowTheLandedRule() {
        let landed = ApproachState(row: row(verdict: .changes, postedAt: posted), artifacts: loaded)
        XCTAssertEqual((0..<4).map(landed.readout(at:)), [.blast, .review, .checker, .review])
        let stopped = ApproachState(row: row(verdict: nil, stage: .gather), artifacts: loaded)
        XCTAssertEqual((0..<4).map(stopped.readout(at:)), [.gathered, .review, .review, .notes])
    }

    func testStyledDropsEveryLink() {
        let text = "See [the docs](https://evil.example/login) and `code` here."
        let styled = FlightText.styled(text)
        XCTAssertTrue(styled.runs.allSatisfy { $0.attributes[AttributeScopes.FoundationAttributes.LinkAttribute.self] == nil })
        XCTAssertTrue(String(styled.characters).contains("the docs"), "the label stays as plain text")
        XCTAssertTrue(String(styled.characters).contains("code"))
    }

    func testDurationReadsInMinutesAndSeconds() {
        XCTAssertEqual(ReviewDetail.duration(0), "0 s")
        XCTAssertEqual(ReviewDetail.duration(42), "42 s")
        XCTAssertEqual(ReviewDetail.duration(192), "3 min 12 s")
        XCTAssertEqual(ReviewDetail.duration(599), "9 min 59 s")
        XCTAssertEqual(ReviewDetail.duration(600), "10 min")
        XCTAssertEqual(ReviewDetail.duration(31 * 60), "31 min")
        XCTAssertEqual(ReviewDetail.duration(59.6), "1 min 0 s", "rounds to the nearest second")
    }
}
