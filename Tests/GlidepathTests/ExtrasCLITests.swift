import XCTest
@testable import Glidepath

final class ExtrasCLITests: XCTestCase {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A UTC date in October 2026.
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Self-review

    func testSelfReviewRunIDReadsTheRunLine() {
        let out = "run 20261026-101010-abc123 (dry run)\nowner/name #5 ana: changes\ntokens: 900\n"
        XCTAssertEqual(Tender.selfReviewRunID(out), "20261026-101010-abc123")
        XCTAssertNil(Tender.selfReviewRunID("no PRs\nrunning later"))
    }

    func testSelfReviewFindingsAreTheRoundsPendingAsks() {
        let pr = OpenPR(n: 5, title: "t", head: "abcdef1234")
        let review = SelfReview(head: "abcdef1234", at: at(26, 9), verdict: "changes",
                                findings: [DraftComment(path: "a.swift", line: 3, side: nil, body: "fix")], done: false)
        let state = TendPR(slug: "o/r", n: 5)
        var withReview = state
        withReview.selfReview = review
        XCTAssertTrue(TendDecision.pendingAsks(pr, state: state, me: "me").isEmpty)
        XCTAssertEqual(TendDecision.pendingAsks(pr, state: withReview, me: "me").map(\.kind), ["self"])
        // With the finding present and no fingerprint yet, the decision is a round.
        XCTAssertEqual(TendDecision.decide(pr, state: withReview, me: "me"), .round(.normal))
        withReview.selfReview?.done = true
        XCTAssertTrue(TendDecision.pendingAsks(pr, state: withReview, me: "me").isEmpty)
    }

    func testFailedSelfReviewLine() {
        let failed = SelfReview(head: "h", at: at(26, 9), verdict: "failed", findings: [], done: true)
        XCTAssertEqual(Approach.selfReviewLine(failed), "Self-review: did not run")
    }

    // MARK: Nudges and Linear

    func testPingBodyNamesTheReviewer() {
        XCTAssertEqual(Tender.pingBody(login: "gadi"), "@gadi, could you take a look when you get a chance? Thanks.")
    }

    func testCanPingOncePerDay() {
        var s = TendPR(slug: "o/r", n: 3)
        XCTAssertTrue(Tender.canPing(s, login: "gadi", now: at(26, 9), calendar: utc))
        s.pinged["gadi"] = at(26, 8)
        XCTAssertFalse(Tender.canPing(s, login: "gadi", now: at(26, 17), calendar: utc))
        XCTAssertTrue(Tender.canPing(s, login: "ana", now: at(26, 17), calendar: utc))
        XCTAssertTrue(Tender.canPing(s, login: "gadi", now: at(27, 9), calendar: utc))
    }

    func testLinearReasonKeys() {
        XCTAssertEqual(Tender.linearReasons(stuck: nil, waits: []), [])
        XCTAssertEqual(Tender.linearReasons(stuck: "Session ended", waits: [(login: "gadi", hours: 26)]),
                       ["stuck:Session ended", "wait:gadi"])
        XCTAssertEqual(Tender.linearReasons(stuck: nil, waits: [(login: "ana", hours: 30), (login: "gadi", hours: 26)]),
                       ["wait:ana", "wait:gadi"])
    }

    func testSplitStatusReadsTheTrailingCode() throws {
        let parts = try XCTUnwrap(Linear.splitStatus("{\"data\":null}\n200"))
        XCTAssertEqual(parts.status, 200)
        XCTAssertEqual(String(decoding: parts.body, as: UTF8.self), "{\"data\":null}")
        XCTAssertNil(Linear.splitStatus("no code here"))
    }

    func testLessonsDueEverySevenDays() {
        XCTAssertTrue(Tender.lessonsDue(last: nil, now: at(26, 9)))
        XCTAssertFalse(Tender.lessonsDue(last: at(20, 9), now: at(26, 9)))
        XCTAssertTrue(Tender.lessonsDue(last: at(19, 9), now: at(26, 9)))
    }

    // MARK: Briefing

    func testSelfReviewAndConsolidationAreNotRounds() {
        var review = RunState.new(id: "a", now: at(26, 8), kind: "tend")
        review.tendAction = "self-review"
        var merge = RunState.new(id: "b", now: at(26, 8), kind: "tend")
        merge.tendAction = "consolidated"
        let briefing = Briefing.compose(since: at(25, 0), now: at(26, 9), runs: [review, merge], landed: [], needs: [])
        XCTAssertEqual(briefing.rounds, 0)
    }

    // MARK: Linear key

    func testLinearKeyShape() {
        XCTAssertTrue(LinearKey.valid("lin_api_abc-123456"))
        XCTAssertFalse(LinearKey.valid("short"))
        XCTAssertFalse(LinearKey.valid("has space in it"))
        XCTAssertFalse(LinearKey.valid("quote\"inside-key"))
        XCTAssertFalse(LinearKey.valid(String(repeating: "a", count: 201)))
    }

    /// A bad key is refused before any Keychain call, so this never touches the login Keychain.
    func testSaveRefusesBadKeyWithoutRunningSecurity() {
        XCTAssertThrowsError(try LinearKey.save("bad key\"; rm -rf ~"))
    }

    func testCommentPostedReadsSuccess() throws {
        XCTAssertTrue(Linear.commentPosted(Data(#"{"data":{"commentCreate":{"success":true}}}"#.utf8)))
        XCTAssertFalse(Linear.commentPosted(Data(#"{"data":{"commentCreate":{"success":false}}}"#.utf8)))
        XCTAssertFalse(Linear.commentPosted(Data(#"{"errors":[{"message":"nope"}]}"#.utf8)))
    }
}
