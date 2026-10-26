import XCTest
@testable import Glidepath

final class ExtrasTests: XCTestCase {
    let home = "/fake/home"

    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A UTC date in October 2026. The 26th is a Monday, the 31st a Saturday.
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Nudge

    func testWeekdayHoursSameDay() {
        XCTAssertEqual(Nudge.weekdayHours(from: at(26, 9), to: at(26, 17), calendar: utc), 8)
    }

    func testWeekdayHoursSkipsWeekend() {
        XCTAssertEqual(Nudge.weekdayHours(from: at(23, 17), to: at(26, 9), calendar: utc), 16)
    }

    func testWeekdayHoursSaturdayToSundayIsZero() {
        let sat = utc.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
        let sun = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 17))!
        XCTAssertEqual(Nudge.weekdayHours(from: sat, to: sun, calendar: utc), 0)
    }

    func testWaitingKeepsOnlyReviewersPastThreshold() {
        let pr = OpenPR(n: 7, title: "t", requested: ["gadi", "ana", "kim"],
                        requestedAt: ["gadi": at(22, 9), "ana": at(26, 8)])
        let waiting = Nudge.waiting(pr, now: at(26, 12), hours: 24, calendar: utc)
        XCTAssertEqual(waiting.map(\.login), ["gadi"])
        XCTAssertEqual(waiting.first?.hours, 51)
    }

    func testWaitingIsEmptyWhenApproved() {
        let pr = OpenPR(n: 7, title: "t", reviewDecision: "APPROVED", requested: ["gadi"],
                        requestedAt: ["gadi": at(22, 9)])
        XCTAssertTrue(Nudge.waiting(pr, now: at(26, 12), hours: 24, calendar: utc).isEmpty)
    }

    // MARK: Describe

    func testRewriteReplacesOnlyTheMarkedSpan() {
        let block = Describe.block(lines: ["a"], checks: [])
        let body = "Intro\n<!-- glidepath -->\nold\n<!-- /glidepath -->\nOutro"
        XCTAssertEqual(Describe.rewrite(body, block: block), "Intro\n" + block + "\nOutro")
    }

    func testRewriteAppendsWhenMarkersMissing() {
        XCTAssertEqual(Describe.rewrite("Body", block: "B"), "Body\n\nB")
    }

    func testRewriteRefusesOnlyOpeningMarker() {
        XCTAssertNil(Describe.rewrite("Body\n<!-- glidepath -->\nx", block: "B"))
    }

    func testRewriteRefusesOnlyClosingMarker() {
        XCTAssertNil(Describe.rewrite("Body\n<!-- /glidepath -->\nx", block: "B"))
    }

    func testRewriteRefusesDuplicatedMarkers() {
        let twice = "<!-- glidepath -->a<!-- /glidepath -->\n<!-- glidepath -->b<!-- /glidepath -->"
        XCTAssertNil(Describe.rewrite(twice, block: "B"))
        XCTAssertNil(Describe.rewrite("<!-- glidepath -->a<!-- /glidepath -->\n<!-- /glidepath -->", block: "B"))
    }

    func testRewriteRefusesCloseBeforeOpen() {
        XCTAssertNil(Describe.rewrite("x<!-- /glidepath -->y<!-- glidepath -->", block: "B"))
    }

    func testRewriteWithNilBodyReturnsBlock() {
        XCTAssertEqual(Describe.rewrite(nil, block: "B"), "B")
    }

    func testBlockWithoutChecks() {
        XCTAssertEqual(Describe.block(lines: ["a", "b"], checks: []),
                       "<!-- glidepath -->\n### Changes since review\n- a\n- b\n<!-- /glidepath -->")
    }

    func testBlockWithChecks() {
        XCTAssertEqual(Describe.block(lines: ["a"], checks: ["swift test"]),
                       "<!-- glidepath -->\n### Changes since review\n- a\n\n### Test plan\n- [x] `swift test`\n<!-- /glidepath -->")
    }

    func testAddingKeepsNewestChanges() {
        var changes: [String] = []
        for i in 0..<12 { changes = Describe.adding("c\(i)", to: changes) }
        XCTAssertEqual(changes.count, 10)
        XCTAssertEqual(changes.first, "c2")
        XCTAssertEqual(changes.last, "c11")
    }

    // MARK: Linear

    func testIssueIdFromTitle() {
        XCTAssertEqual(Linear.issueId(title: "OPS-123 fix login", branch: "main"), "OPS-123")
    }

    func testIssueIdFromBranch() {
        XCTAssertEqual(Linear.issueId(title: "fix login", branch: "yazan/ops-123-foo"), "OPS-123")
    }

    func testIssueIdNone() {
        XCTAssertNil(Linear.issueId(title: "fix login", branch: "main"))
    }

    func testLookupBodyKeepsIdInVariables() throws {
        let body = try object(Linear.lookupBody(id: "OPS-123"))
        let query = try XCTUnwrap(body["query"] as? String)
        XCTAssertTrue(query.contains("$id"))
        XCTAssertFalse(query.contains("OPS-123"))
        XCTAssertEqual((body["variables"] as? [String: String])?["id"], "OPS-123")
    }

    func testCommentBodyKeepsValuesInVariables() throws {
        let text = "Looks blocked by \"quotes\" $x"
        let body = try object(Linear.commentBody(issueUUID: "uuid-1", body: text))
        let query = try XCTUnwrap(body["query"] as? String)
        XCTAssertTrue(query.contains("$issueId"))
        XCTAssertTrue(query.contains("$body"))
        XCTAssertFalse(query.contains("uuid-1"))
        XCTAssertFalse(query.contains("Looks blocked"))
        let variables = try XCTUnwrap(body["variables"] as? [String: String])
        XCTAssertEqual(variables["issueId"], "uuid-1")
        XCTAssertEqual(variables["body"], text)
    }

    func testParseIssueUUID() {
        XCTAssertEqual(Linear.parseIssueUUID(Data(#"{"data":{"issue":{"id":"uuid-1"}}}"#.utf8)), "uuid-1")
        XCTAssertNil(Linear.parseIssueUUID(Data(#"{"data":{"issue":null}}"#.utf8)))
        XCTAssertNil(Linear.parseIssueUUID(Data("garbage".utf8)))
    }

    // MARK: Briefing

    func testComposeCountsRunsSinceTheLastBriefing() {
        var round = RunState.new(id: "a", now: at(25, 10), kind: "tend")
        round.tokens = 100
        round.tendAction = "fixed"
        round.tendThreads = [ThreadVerdict(id: "t1", author: "ana", quote: "q", verdict: "agree", reply: nil, posted: false),
                             ThreadVerdict(id: "t2", author: "ana", quote: "q", verdict: "disagree", reply: "r", posted: true)]
        round.council = [CouncilRecord(topic: "t", seats: [], chair: nil, outcome: "act")]
        var quiet = RunState.new(id: "c", now: at(26, 8))
        quiet.tokens = 50
        var old = RunState.new(id: "b", now: at(20, 10), kind: "tend")
        old.tokens = 999
        old.tendAction = "reran"
        let landed = [TendLanded(slug: "o/r", n: 5, title: "Fix", sha: "s", parent: "p", at: at(25, 9), status: "ok"),
                      TendLanded(slug: "o/r", n: 4, title: "Old", sha: "s", parent: "p", at: at(20, 9), status: "ok")]
        let needs = [NeedsItem(id: "x", slug: "o/r", n: 5, title: "Fix", kind: "held", detail: "Fix held · x"),
                     NeedsItem(id: "y", slug: "o/r", n: 5, title: "Fix", kind: "land", detail: "Ready")]

        let briefing = Briefing.compose(since: at(24, 0), now: at(26, 9), runs: [round, quiet, old], landed: landed,
                                        needs: needs)

        XCTAssertEqual(briefing.at, at(26, 9))
        XCTAssertEqual(briefing.landed, ["#5 Fix"])
        XCTAssertEqual(briefing.blocked, ["#5 · Fix held · x"])
        XCTAssertEqual(briefing.rounds, 1)
        XCTAssertEqual(briefing.threads, 2)
        XCTAssertEqual(briefing.councils, 1)
        XCTAssertEqual(briefing.tokens, 100)
    }

    func testIsDue() {
        let time = ScheduleTime("08:00")!
        XCTAssertFalse(Briefing.isDue(now: at(26, 7, 30), last: nil, time: time, days: .all, calendar: utc))
        XCTAssertTrue(Briefing.isDue(now: at(26, 9), last: nil, time: time, days: .all, calendar: utc))
        XCTAssertTrue(Briefing.isDue(now: at(26, 9), last: at(26, 7), time: time, days: .all, calendar: utc))
        XCTAssertFalse(Briefing.isDue(now: at(26, 9), last: at(26, 8, 30), time: time, days: .all, calendar: utc))
        XCTAssertFalse(Briefing.isDue(now: at(31, 9), last: nil, time: time, days: .weekdays, calendar: utc))
        XCTAssertTrue(Briefing.isDue(now: at(25, 9), last: nil, time: time, days: .all, calendar: utc))
        XCTAssertFalse(Briefing.isDue(now: at(25, 9), last: nil, time: time, days: .weekdays, calendar: utc))
        XCTAssertTrue(Briefing.isDue(now: at(26, 9), last: nil, time: time, days: .weekdays, calendar: utc))
    }

    // MARK: Playbook and Lessons

    func testDropStaleKeepsLessonsWithinDays() {
        let now = at(26, 12)
        let playbook = Playbook(commands: [], lessons: [
            Playbook.Lesson(text: "old", source: "pushback", date: now.addingTimeInterval(-61 * 86_400)),
            Playbook.Lesson(text: "recent", source: "pushback", date: now.addingTimeInterval(-59 * 86_400)),
        ])
        XCTAssertEqual(playbook.dropStale(now: now, days: 60).lessons.map(\.text), ["recent"])
    }

    func testParseListReadsBullets() {
        XCTAssertEqual(Lessons.parseList("- a\n- b\n", max: 5), ["a", "b"])
    }

    func testParseListRejectsEmpty() {
        XCTAssertNil(Lessons.parseList(" \n\n", max: 5))
    }

    func testParseListRejectsLinesWithoutBullet() { XCTAssertNil(Lessons.parseList("Here is the list:\n- a\n- b", max: 5)) }

    func testParseListRejectsTooMany() {
        XCTAssertNil(Lessons.parseList("- a\n- b\n- c", max: 2))
    }

    func testParseListLengthLimit() {
        XCTAssertNil(Lessons.parseList("- " + String(repeating: "x", count: 161), max: 5))
        XCTAssertEqual(Lessons.parseList("- " + String(repeating: "x", count: 160), max: 5), [String(repeating: "x", count: 160)])
    }

    // MARK: Config

    func testSelfReviewConfigDefaultsWhenTableAbsent() throws {
        let c = try Config.parse("schedule = [\"07:00\"]\n", home: home)
        XCTAssertFalse(c.tend.selfReview)
        XCTAssertEqual(c.tend.nudgeHours, 24)
        XCTAssertEqual(c.tend.briefingTime, ScheduleTime("08:00"))
    }

    func testNudgeHoursZeroThrows() {
        XCTAssertThrowsError(try Config.parse("schedule = [\"07:00\"]\n[tend]\nnudge_hours = 0\n", home: home))
    }

    func testBriefingTimeMustBeHHMM() {
        XCTAssertThrowsError(try Config.parse("schedule = [\"07:00\"]\n[tend]\nbriefing_time = \"8am\"\n", home: home))
    }

    func testSelfReviewParses() throws {
        let c = try Config.parse("schedule = [\"07:00\"]\n[tend]\nself_review = true\n", home: home)
        XCTAssertTrue(c.tend.selfReview)
    }

    func testSelfReviewConfigRoundTrips() throws {
        let text = "schedule = [\"07:00\"]\n[tend]\nself_review = true\nnudge_hours = 48\nbriefing_time = \"07:30\"\n"
        let config = try Config.parse(text, home: home)
        XCTAssertEqual(try Config.parse(config.render(), home: home), config)
    }

    // MARK: Older JSON

    func testOlderTendFileDecodesWithDefaults() throws {
        let pr = try RunStore.decoder().decode(TendPR.self, from: Data(#"{"slug":"yazan/glidepath","n":4}"#.utf8))
        XCTAssertNil(pr.selfReview)
        XCTAssertFalse(pr.wasDraft)
        XCTAssertEqual(pr.changes, [])
        XCTAssertEqual(pr.pinged, [:])
        XCTAssertEqual(pr.linearPosted, [])
    }

    func testOlderPlaneDecodesWithoutSelfReview() throws {
        let plane = ApproachPlane(slug: "o/r", n: 1, title: "t", url: "u", phase: .waiting, marker: 1, label: "Waiting on review",
                                  waitingOn: nil, lane: 0, stackIndex: nil, off: false, gates: [], ci: "none")
        var fields = try object(RunStore.encoder().encode(plane))
        fields.removeValue(forKey: "selfReview")
        let older = try RunStore.decoder().decode(ApproachPlane.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertNil(older.selfReview)
        XCTAssertEqual(older.slug, "o/r")
    }

    // MARK: Self-review

    func testSelfAsksForChanges() {
        let review = SelfReview(head: "abcdef1234", at: at(26, 9), verdict: "changes",
                                findings: [DraftComment(path: "a.swift", line: 3, side: nil, body: "first"),
                                           DraftComment(path: "b.swift", line: 9, side: nil, body: "second")],
                                done: false)
        let asks = Threads.selfAsks(review, answered: [])
        XCTAssertEqual(asks.map(\.id), ["self-abcdef1-0", "self-abcdef1-1"])
        XCTAssertEqual(Set(asks.map(\.kind)), ["self"])
        XCTAssertEqual(Set(asks.map(\.author)), ["self-review"])
        XCTAssertEqual(Threads.selfAsks(review, answered: ["self-abcdef1-0"]).map(\.id), ["self-abcdef1-1"])
    }

    func testSelfAsksEmptyWhenDoneOrApproved() {
        let finding = DraftComment(path: "a.swift", line: 3, side: nil, body: "first")
        let done = SelfReview(head: "abcdef1234", at: at(26, 9), verdict: "changes", findings: [finding], done: true)
        let clean = SelfReview(head: "abcdef1234", at: at(26, 9), verdict: "clean", findings: [finding], done: false)
        XCTAssertTrue(Threads.selfAsks(done, answered: []).isEmpty)
        XCTAssertTrue(Threads.selfAsks(clean, answered: []).isEmpty)
    }

    func testSelfReviewLine() {
        let finding = DraftComment(path: "a.swift", line: 3, side: nil, body: "x")
        func review(_ verdict: String, _ findings: [DraftComment]) -> SelfReview {
            SelfReview(head: "h", at: at(26, 9), verdict: verdict, findings: findings, done: false)
        }
        XCTAssertEqual(Approach.selfReviewLine(review("changes", [finding, finding])), "Self-review: 2 findings")
        XCTAssertEqual(Approach.selfReviewLine(review("changes", [finding])), "Self-review: 1 finding")
        XCTAssertEqual(Approach.selfReviewLine(review("clean", [])), "Self-review: clean")
    }

    func testNeedsIncludesNudge() {
        let pr = OpenPR(n: 9, title: "t")
        let items = Approach.needs("o/r", pr, state: nil, nudges: [(login: "gadi", hours: 26)])
        XCTAssertEqual(items, [NeedsItem(id: "o/r#9/wait-gadi", slug: "o/r", n: 9, title: "t", kind: "blocked",
                                         detail: "Waiting 26 h on gadi")])
    }

    func testNoPingRowForADraftOrAHandsOffPR() {
        var draft = OpenPR(n: 9, title: "t")
        draft.isDraft = true
        XCTAssertTrue(Approach.needs("o/r", draft, state: nil, nudges: [(login: "gadi", hours: 26)]).isEmpty)
        var off = TendPR(slug: "o/r", n: 9)
        off.off = true
        XCTAssertTrue(Approach.needs("o/r", OpenPR(n: 9, title: "t"), state: off, nudges: [(login: "gadi", hours: 26)]).isEmpty)
    }

    // MARK: Autopilot

    func testNudgeActsOnlyUnderAutopilot() {
        XCTAssertEqual(Autopilot.actor(.nudge, autopilot: true, push: .untilApproved), .act)
        XCTAssertEqual(Autopilot.actor(.nudge, autopilot: false, push: .untilApproved), .you)
    }
}
