import XCTest
@testable import Glidepath

final class TendCommentsTests: XCTestCase {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    /// A PR with the given conversation. Checks are green unless given.
    func pr(threads: [ReviewThread] = [], reviews: [ReviewInfo] = [], comments: [PRComment] = [],
            checks: [CheckState] = [CheckState(name: "test", status: "COMPLETED", conclusion: "SUCCESS")]) -> OpenPR {
        var p = OpenPR()
        p.n = 7
        p.head = "sha7"
        p.branch = "fix"
        p.base = "main"
        p.checks = checks
        p.threads = threads
        p.reviews = reviews
        p.comments = comments
        return p
    }

    func comment(_ id: String, _ author: String, _ body: String, db: Int? = nil) -> ThreadComment {
        ThreadComment(id: id, databaseId: db, author: author, body: body, path: "Sources/a.swift", line: 12)
    }

    func thread(_ id: String, _ comments: [ThreadComment], resolved: Bool = false) -> ReviewThread {
        ReviewThread(id: id, isResolved: resolved, comments: comments)
    }

    func plain(_ id: String, _ author: String, _ body: String) -> PRComment {
        PRComment(id: id, databaseId: 5, author: author, body: body)
    }

    // MARK: Threads

    func testIsBot() {
        XCTAssertTrue(Threads.isBot("copilot-pull-request-reviewer[bot]"))
        XCTAssertTrue(Threads.isBot("coderabbitai"))
        XCTAssertTrue(Threads.isBot("github-actions"))
        XCTAssertTrue(Threads.isBot("renovate[bot]"))
        XCTAssertFalse(Threads.isBot("alice"))
    }

    func testIsNoise() {
        XCTAssertTrue(Threads.isNoise("LGTM!"))
        XCTAssertTrue(Threads.isNoise("looks good"))
        XCTAssertTrue(Threads.isNoise("👍"))
        XCTAssertTrue(Threads.isNoise("+1"))
        XCTAssertFalse(Threads.isNoise("looks good to me, but rename this"))
        XCTAssertFalse(Threads.isNoise("Please rename this variable"))
        XCTAssertFalse(Threads.isNoise(""))
    }

    func testActionableThreads() {
        let open = pr(threads: [thread("t1", [comment("c1", "alice", "rename this")])])
        let asks = Threads.actionable(open, me: "dev", answered: [])
        XCTAssertEqual(asks, [Ask(id: "t1", kind: "thread", author: "alice", isBot: false, body: "rename this",
                                  path: "Sources/a.swift", line: 12, databaseId: nil,
                                  thread: [comment("c1", "alice", "rename this")])])

        // The last word is ours: waiting on the reviewer.
        let ours = pr(threads: [thread("t2", [comment("c2", "alice", "why?"), comment("c3", "dev", "because")])])
        XCTAssertEqual(Threads.actionable(ours, me: "dev", answered: []), [])

        let resolved = pr(threads: [thread("t3", [comment("c4", "alice", "rename")], resolved: true)])
        XCTAssertEqual(Threads.actionable(resolved, me: "dev", answered: []), [])

        let bot = pr(threads: [thread("t4", [comment("c5", "coderabbitai", "nit: typo", db: 9)])])
        let botAsk = Threads.actionable(bot, me: "dev", answered: []).first
        XCTAssertEqual(botAsk?.isBot, true)
        XCTAssertEqual(botAsk?.databaseId, 9)

        // Our login in another case is still ours.
        XCTAssertEqual(Threads.actionable(ours, me: "DEV", answered: []), [])
    }

    func testActionableReviewsAndComments() {
        let review = ReviewInfo(id: "r1", author: "bob", state: "CHANGES_REQUESTED", body: "Split this PR.", databaseId: 3)
        let withReview = pr(reviews: [review])
        XCTAssertEqual(Threads.actionable(withReview, me: "dev", answered: []).map(\.kind), ["review"])
        XCTAssertEqual(Threads.actionable(withReview, me: "dev", answered: ["r1"]), [])
        XCTAssertEqual(Threads.actionable(pr(reviews: [ReviewInfo(id: "r2", author: "bob", state: "COMMENTED", body: "hm")]),
                                          me: "dev", answered: []), [])
        XCTAssertEqual(Threads.actionable(pr(reviews: [ReviewInfo(id: "r3", author: "bob", state: "CHANGES_REQUESTED")]),
                                          me: "dev", answered: []), [])
        XCTAssertEqual(Threads.actionable(pr(reviews: [ReviewInfo(id: "r4", author: "dev", state: "CHANGES_REQUESTED",
                                                                  body: "x")]), me: "dev", answered: []), [])

        let chat = pr(comments: [plain("p1", "carol", "Can you add a test?"), plain("p2", "carol", "LGTM"),
                                 plain("p3", "dev", "Sure"), plain("p4", "carol", "Thanks")])
        XCTAssertEqual(Threads.actionable(chat, me: "dev", answered: []).map(\.id), ["p1", "p4"])
        XCTAssertEqual(Threads.actionable(chat, me: "dev", answered: ["p1"]).map(\.id), ["p4"])
    }

    // MARK: ReplyGuard

    func testReplyGuard() {
        let slug = "acme/api"
        XCTAssertNil(ReplyGuard.check("Fine by me.", author: "alice", slug: slug, n: 7))
        XCTAssertNotNil(ReplyGuard.check(String(repeating: "a", count: 601), author: "alice", slug: slug, n: 7))
        XCTAssertNil(ReplyGuard.check(String(repeating: "a", count: 600), author: "alice", slug: slug, n: 7))
        XCTAssertNotNil(ReplyGuard.check("Thanks @bob", author: "alice", slug: slug, n: 7))
        XCTAssertNil(ReplyGuard.check("Thanks @Alice", author: "alice", slug: slug, n: 7))
        XCTAssertNil(ReplyGuard.check("Mail dev@example.com", author: "alice", slug: slug, n: 7))
        XCTAssertNotNil(ReplyGuard.check("See https://example.com/docs", author: "alice", slug: slug, n: 7))
        XCTAssertNotNil(ReplyGuard.check("Fixed in https://github.com/acme/api/pull/8/commits/abc1234",
                                         author: "alice", slug: slug, n: 7))
        XCTAssertNotNil(ReplyGuard.check("See https://github.com/acme/apix/commit/abc1234", author: "alice", slug: slug, n: 7))
        XCTAssertNotNil(ReplyGuard.check("See https://github.com/acme/api/commit/xyz", author: "alice", slug: slug, n: 7))
        XCTAssertNil(ReplyGuard.check("Fixed in https://github.com/acme/api/commit/abc1234", author: "alice", slug: slug, n: 7))
        XCTAssertNil(ReplyGuard.check("Fixed in https://github.com/acme/api/pull/7/commits/abcdef1",
                                      author: "alice", slug: slug, n: 7))
    }

    // MARK: Fingerprint and decision

    func testFullFingerprintTracksNewActivityNotOrder() {
        let t1 = thread("t1", [comment("c1", "alice", "a")])
        let t2 = thread("t2", [comment("c2", "bob", "b")])
        let base = pr(threads: [t1, t2])
        let reordered = pr(threads: [t2, t1])
        XCTAssertEqual(Fingerprint.full(base, me: "dev"), Fingerprint.full(reordered, me: "dev"))

        var replied = base
        replied.threads[0].comments.append(comment("c3", "alice", "still wrong"))
        XCTAssertNotEqual(Fingerprint.full(base, me: "dev"), Fingerprint.full(replied, me: "dev"))

        // Our own comment on the conversation does not change it; another's does.
        let mine = pr(comments: [plain("p1", "dev", "on it")])
        XCTAssertEqual(Fingerprint.full(pr(), me: "dev"), Fingerprint.full(mine, me: "dev"))
        XCTAssertNotEqual(Fingerprint.full(pr(), me: "dev"),
                          Fingerprint.full(pr(comments: [plain("p2", "carol", "hi")]), me: "dev"))
        XCTAssertTrue(Fingerprint.full(base, me: "dev").hasPrefix(Fingerprint.ci(base) + "|"))
    }

    func testDecideRoundsOnThreadsOnly() {
        let open = pr(threads: [thread("t1", [comment("c1", "alice", "rename")])])
        var state = TendPR(slug: "acme/api", n: 7)
        XCTAssertEqual(TendDecision.decide(open, state: state, me: "dev"), .round(.normal))
        state.fingerprint = Fingerprint.full(open, me: "dev")
        XCTAssertEqual(TendDecision.decide(open, state: state, me: "dev"), .idle)
        state.fingerprint = nil
        XCTAssertEqual(TendDecision.decide(open, state: state, me: "dev"), .round(.normal))

        // CI still running: wait for it even with a thread waiting.
        var running = open
        running.checks = [CheckState(name: "test", status: "IN_PROGRESS", conclusion: nil)]
        XCTAssertEqual(TendDecision.decide(running, state: TendPR(slug: "acme/api", n: 7), me: "dev"), .idle)

        // Approved and red: urgent, as before.
        var approvedRed = pr(threads: open.threads, checks: [CheckState(name: "test", status: "COMPLETED", conclusion: "FAILURE")])
        approvedRed.reviewDecision = "APPROVED"
        XCTAssertEqual(TendDecision.decide(approvedRed, state: TendPR(slug: "acme/api", n: 7), me: "dev"), .round(.urgent))

        // Our reply went last: nothing to do.
        let answered = pr(threads: [thread("t2", [comment("c2", "alice", "why"), comment("c3", "dev", "because")])])
        XCTAssertEqual(TendDecision.decide(answered, state: TendPR(slug: "acme/api", n: 7), me: "dev"), .idle)
    }

    // MARK: Autopilot

    func testDisagreeUnclearAndLowConfidenceActors() {
        XCTAssertEqual(Autopilot.actor(.disagree, autopilot: true, push: .untilApproved, disagree: .draft), .council)
        XCTAssertEqual(Autopilot.actor(.disagree, autopilot: true, push: .untilApproved, disagree: .replyResolve), .council)
        XCTAssertEqual(Autopilot.actor(.disagree, autopilot: false, push: .untilApproved, disagree: .draft), .you)
        XCTAssertEqual(Autopilot.actor(.disagree, autopilot: false, push: .untilApproved, disagree: .replyResolve), .act)
        XCTAssertEqual(Autopilot.actor(.disagree, autopilot: false, push: .always), .you)
        for action in [TendAction.unclear, .lowConfidence] {
            XCTAssertEqual(Autopilot.actor(action, autopilot: true, push: .untilApproved), .council)
            XCTAssertEqual(Autopilot.actor(action, autopilot: false, push: .untilApproved), .you)
        }
    }

    // MARK: Council

    func seat(_ vote: String, security: Bool = false) -> Seat {
        Seat(lens: "risk", vote: vote, reason: "r", confidence: "high", security: security)
    }

    func testParseSeatReadsLastVoteLine() {
        let text = """
        Looking at the diff.
        ```json
        {"vote": "hold", "reason": "old", "confidence": "low", "security": false}
        ```
        {"vote": "act", "reason": "Test fix is in scope.", "confidence": "high", "security": false}
        """
        XCTAssertEqual(Council.parseSeat(text, lens: "correctness"), Seat(lens: "correctness", vote: "act",
                       reason: "Test fix is in scope.", confidence: "high", security: false))
        XCTAssertNil(Council.parseSeat("{\"vote\": \"maybe\"}", lens: "risk"))
        XCTAssertNil(Council.parseSeat("no json here", lens: "risk"))
        let long = String(repeating: "x", count: 300)
        let clipped = Council.parseSeat("{\"vote\": \"hold\", \"reason\": \"\(long)\"}", lens: "intent")
        XCTAssertEqual(clipped?.reason.count, 200)
        XCTAssertEqual(clipped?.confidence, "low")
        XCTAssertEqual(clipped?.security, false)
    }

    func testCouncilOutcome() {
        XCTAssertEqual(Council.outcome([seat("act"), seat("act"), seat("act")]), .unanimous("act"))
        XCTAssertEqual(Council.outcome([seat("hold"), seat("hold"), seat("hold")]), .unanimous("hold"))
        XCTAssertEqual(Council.outcome([seat("act"), seat("hold"), seat("act")]), .split)
        XCTAssertEqual(Council.outcome([seat("act"), seat("act", security: true), seat("act")]), .stop)
        XCTAssertEqual(Council.outcome([seat("act"), seat("act")]), .stop)
    }

    func testParseChair() {
        let chair = Council.parseChair("Weighing it.\n{\"decision\": \"act\", \"line\": \"Post the reply and resolve.\"}")
        XCTAssertEqual(chair?.decision, "act")
        XCTAssertEqual(chair?.line, "Post the reply and resolve.")
        XCTAssertEqual(Council.parseChair("{\"decision\": \"unsure\", \"line\": \"?\"}")?.decision, "unsure")
        XCTAssertNil(Council.parseChair("{\"decision\": \"post\"}"))
    }

    func testCouncilTowerText() {
        let unanimous = CouncilRecord(topic: "t", seats: [seat("act"), seat("act"), seat("act")], chair: nil, outcome: "act")
        XCTAssertEqual(Council.towerText(unanimous), "Council 3–0, act")
        let split = CouncilRecord(topic: "t", seats: [seat("act"), seat("act"), seat("hold")], chair: "act", outcome: "act")
        XCTAssertEqual(Council.towerText(split), "Council 2–1, chair: act")
        let stopped = CouncilRecord(topic: "t", seats: [seat("act"), seat("act", security: true), seat("hold")],
                                    chair: nil, outcome: "stop")
        XCTAssertEqual(Council.towerText(stopped), "Council could not settle")
    }

    func testCouncilCountResetsOnANewDay() throws {
        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-council-\(UUID().uuidString)", env: [:])
        XCTAssertEqual(Council.countToday(paths: paths, now: at(26, 9)), 0)
        try Council.bump(paths: paths, now: at(26, 9))
        try Council.bump(paths: paths, now: at(26, 15))
        XCTAssertEqual(Council.countToday(paths: paths, now: at(26, 10)), 2)
        XCTAssertEqual(Council.countToday(paths: paths, now: at(27, 9)), 0)
    }

    // MARK: Lessons

    func testLessonParse() {
        XCTAssertEqual(Lessons.parse("- Run `make lint` before the tests.\n"), "Run `make lint` before the tests.")
        XCTAssertEqual(Lessons.parse("Thinking.\nalice wants tests first"), "alice wants tests first")
        XCTAssertNil(Lessons.parse("NONE"))
        XCTAssertNil(Lessons.parse("none.\n"))
        XCTAssertNil(Lessons.parse("  \n"))
        XCTAssertEqual(Lessons.parse(String(repeating: "a", count: 200))?.count, 160)
    }

    // MARK: Config and state

    func testDisagreeConfig() throws {
        XCTAssertEqual(try Config.parse("schedule = [\"07:00\"]\n", home: "/fake/home").tend.disagree, .draft)
        let c = try Config.parse("[tend]\ndisagree = \"reply_resolve\"\n", home: "/fake/home")
        XCTAssertEqual(c.tend.disagree, .replyResolve)
        XCTAssertTrue(c.render().contains("disagree = \"reply_resolve\""))
        let back = try Config.parse(c.render(), home: "/fake/home")
        XCTAssertEqual(back.tend.disagree, .replyResolve)
        XCTAssertFalse(try Config.parse("[tend]\nenabled = true\n", home: "/fake/home").render().contains("disagree"))
        XCTAssertThrowsError(try Config.parse("[tend]\ndisagree = \"argue\"\n", home: "/fake/home"))
        let set = ConfigEditor.setTendDisagree(Config(schedule: [], limits: Limits(), repos: []), .replyResolve)
        XCTAssertEqual(set.tend.disagree, .replyResolve)
    }

    func testVersion16TendPRDecodes() throws {
        let json = """
        {"slug":"acme/api","n":3,"roundsToday":1,"triesByHead":{"sha3":1},"rerunsByHead":{},\
        "held":{"commit":"abc","summary":"x","at":"2026-10-26T09:00:00Z"},"off":false,"pendingRan":[]}
        """
        let s = try RunStore.decoder().decode(TendPR.self, from: Data(json.utf8))
        XCTAssertEqual(s.roundsToday, 1)
        XCTAssertEqual(s.held?.commit, "abc")
        XCTAssertEqual(s.held?.replies, [])
        XCTAssertEqual(s.answered, [])
        XCTAssertEqual(s.calls, [])
        XCTAssertEqual(s.rereq, [])
    }

    func testCallsShowInNeedsAndGates() {
        var p = pr(threads: [thread("t1", [comment("c1", "alice", "rename")])])
        p.head = "sha7"
        var state = TendPR(slug: "acme/api", n: 7)
        state.calls = [YourCall(id: "c1", kind: "thread", author: "alice", quote: "rename", draft: "Done.", at: at(26, 9))]
        XCTAssertEqual(Approach.needs("acme/api", p, state: state), [NeedsItem(
            id: "acme/api#7/c1", slug: "acme/api", n: 7, title: "", kind: "call",
            detail: "Your call · alice: \"rename\" · draft reply ready")])
        let threads = Approach.gates(p, state: state).first { $0.name == "Threads" }
        XCTAssertEqual(threads, Gate(name: "Threads", state: .wait, detail: "1 open · 1 need your call", who: "you"))
    }
}
