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
