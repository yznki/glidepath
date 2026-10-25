import XCTest
@testable import Glidepath

final class TendCoreTests: XCTestCase {
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

    private func decide(_ cls: WorkClass, _ usage: UsageState, at now: Date) -> SpendDecision {
        UsageGuard.decide(cls, usage, reserve: 40, quiet: QuietHours.parse("22:00-07:00,sat,sun")!, now: now, calendar: utc)
    }

    // MARK: Config

    func testTendDefaultsWhenTableAbsent() throws {
        let c = try Config.parse("schedule = [\"07:00\"]\n", home: home)
        XCTAssertEqual(c.tend, TendConfig())
        XCTAssertFalse(c.tend.enabled)
        XCTAssertEqual(c.tend.push, .untilApproved)
        XCTAssertEqual(c.tend.roundsPerDay, 5)
        XCTAssertEqual(c.tend.usageReserve, 40)
        XCTAssertEqual(c.tend.quietHours, QuietHours.parse("22:00-07:00,sat,sun"))
        XCTAssertNil(c.claudeConfigDir)
    }

    func testTendTableParses() throws {
        let c = try Config.parse("""
        claude_config_dir = "~/alt/claude"
        [tend]
        enabled = true
        push = "always"
        rounds_per_day = 3
        advisor = "opus"
        usage_reserve = 0
        quiet_hours = "23:00-06:00"
        [[repo]]
        slug = "acme/api"
        tend = true
        """, home: home)
        XCTAssertEqual(c.claudeConfigDir, "/fake/home/alt/claude")
        XCTAssertTrue(c.tend.enabled)
        XCTAssertEqual(c.tend.push, .always)
        XCTAssertEqual(c.tend.roundsPerDay, 3)
        XCTAssertEqual(c.tend.advisor, .opus)
        XCTAssertEqual(c.tend.usageReserve, 0)
        XCTAssertEqual(c.tend.quietHours, QuietHours.parse("23:00-06:00"))
        XCTAssertTrue(c.repos[0].tend)
    }

    func testTendRejectsBadValues() {
        let bad = [
            "[tend]\npush = \"never\"\n",
            "[tend]\nrounds_per_day = 0\n",
            "[tend]\ntries_per_head = 0\n",
            "[tend]\nmax_fix_lines = -1\n",
            "[tend]\nadvisor = \"sonnet\"\n",
            "[tend]\nusage_reserve = 91\n",
            "[tend]\nusage_reserve = \"40\"\n",
            "[tend]\nquiet_hours = \"late\"\n",
            "[tend]\nquiet_hours = \"22:00-07:00,funday\"\n",
            "[tend]\nenabled = \"yes\"\n",
            "tend = 1\n",
            "claude_config_dir = \"relative/claude\"\n",
            "[[repo]]\nslug = \"a/b\"\ntend = \"yes\"\n",
        ]
        for text in bad {
            XCTAssertThrowsError(try Config.parse(text, home: home), text)
        }
    }

    func testTendRenderWritesNonDefaultsAndKeepsUnknownKeys() throws {
        let original = try Config.parse("""
        schedule = ["07:00"]
        claude_config_dir = "/abs/claude"
        [tend]
        enabled = true
        max_fix_lines = 0
        registries = ["example.com"]
        future_knob = { on = true }
        [[repo]]
        slug = "acme/api"
        tend = true
        """, home: home)
        let text = original.render()
        XCTAssertTrue(text.contains("\n[tend]\nenabled = true\n"))
        XCTAssertFalse(text.contains("rounds_per_day"))
        XCTAssertTrue(text.contains("future_knob = { on = true }"))
        let again = try Config.parse(text, home: home)
        XCTAssertEqual(again, original)
        XCTAssertEqual(again.tend.extras["future_knob"], .table(["on": .bool(true)]))
        XCTAssertEqual(again.repos[0].tend, true)
    }

    func testDefaultTendWritesNoSection() throws {
        let text = try Config.parse("schedule = [\"07:00\"]\n", home: home).render()
        XCTAssertFalse(text.contains("[tend]"))
    }

    // MARK: Setup writers

    func testClaudeAccountSeparateAndSame() throws {
        let base = try Config.parse("schedule = [\"07:00\"]\n", home: home)
        var c = ConfigEditor.setClaudeAccount(base, separate: true, home: home)
        XCTAssertEqual(c.claudeConfigDir, "/fake/home/.config/glidepath/claude")
        XCTAssertEqual(c.tend.usageReserve, 0)
        XCTAssertEqual(try Config.parse(c.render(), home: home), c)
        c = ConfigEditor.setClaudeAccount(c, separate: false, home: home)
        XCTAssertNil(c.claudeConfigDir)
        XCTAssertEqual(c.tend.usageReserve, 40)
    }

    func testTendSettersValidateAndRoundTrip() throws {
        let base = try ConfigEditor.addRepo(Config.parse("schedule = [\"07:00\"]\n", home: home),
                                            RepoConfig(slug: "acme/api", clone: "/fake/home/clones/api"))
        var c = ConfigEditor.setTendEnabled(base, true)
        XCTAssertTrue(c.tend.enabled)
        XCTAssertEqual(c.tend.advisor, .opus)
        c = try ConfigEditor.setTendRoundsPerDay(c, 8)
        XCTAssertThrowsError(try ConfigEditor.setTendRoundsPerDay(c, 0))
        XCTAssertThrowsError(try ConfigEditor.setUsageReserve(c, 91))
        XCTAssertThrowsError(try ConfigEditor.setQuietHours(c, "nope"))
        c = try ConfigEditor.setQuietHours(c, "21:00-08:00,sun")
        c = try ConfigEditor.setRepoTend(c, slug: "acme/api", true)
        XCTAssertTrue(c.repos[0].tend)
        XCTAssertEqual(try Config.parse(c.render(), home: home), c)
    }

    // MARK: Quiet hours

    func testQuietHoursWrapsMidnightAndCoversWeekends() throws {
        let q = try XCTUnwrap(QuietHours.parse("22:00-07:00,sat,sun"))
        XCTAssertEqual(q.text, "22:00-07:00,sat,sun")
        XCTAssertEqual(QuietHours.parse(q.text), q)
        XCTAssertTrue(q.contains(at(26, 23, 30), calendar: utc))
        XCTAssertTrue(q.contains(at(27, 6, 59), calendar: utc))
        XCTAssertFalse(q.contains(at(27, 7), calendar: utc))
        XCTAssertFalse(q.contains(at(26, 12), calendar: utc))
        XCTAssertTrue(q.contains(at(31, 12), calendar: utc))
        XCTAssertEqual(q.nextStart(after: at(26, 12), calendar: utc), at(26, 22))
        XCTAssertNil(try XCTUnwrap(QuietHours.parse("10:00-10:00")).nextStart(after: at(26, 12), calendar: utc))
    }

    // MARK: Usage guard

    func testEventsAndResultTextReadStreamLines() {
        let stream = """
        {"type":"assistant","message":{"id":"m1","usage":{"input_tokens":5}}}
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour","utilization":0.72,"resetsAt":1761500000}}
        {"type":"result","result":"All done."}
        """
        let now = at(26, 12)
        XCTAssertEqual(UsageGuard.events(stream: stream, now: now), [
            UsageWindow(type: "five_hour", utilization: 0.72, resetsAt: Date(timeIntervalSince1970: 1_761_500_000), seen: now),
        ])
        XCTAssertEqual(UsageGuard.resultText(stream: stream), "All done.")
        // The 2.1.310 shape: windows nested under unifiedWindows, read one per window.
        let nested = """
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1792979400,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.08,"resetsAt":1792979400,"status":"allowed"},"seven_day":{"utilization":0.5,"status":"allowed"}}}}
        """
        XCTAssertEqual(UsageGuard.events(stream: nested, now: now), [
            UsageWindow(type: "five_hour", utilization: 0.08, resetsAt: Date(timeIntervalSince1970: 1_792_979_400), seen: now),
            UsageWindow(type: "seven_day", utilization: 0.5, resetsAt: nil, seen: now),
        ])
    }

    func testDecideNowWaitStopDeferredAndExpired() {
        let monday = at(26, 12)
        var usage = UsageState()
        XCTAssertEqual(decide(.normal, usage, at: monday), .now)

        // 72% used with a 40% reserve is over the line. The window resets at 13:00.
        usage.record([UsageWindow(type: "five_hour", utilization: 0.72, resetsAt: at(26, 13), seen: monday)])
        XCTAssertEqual(decide(.normal, usage, at: monday), .wait(until: at(26, 13), reason: "Paused for usage · resets 13:00"))
        XCTAssertEqual(decide(.urgent, usage, at: monday), .stop("Usage reserve reached · resets 13:00"))
        // Deferred work waits for quiet hours, and runs in them.
        XCTAssertEqual(decide(.deferred, usage, at: monday), .wait(until: at(26, 22), reason: "Waiting for quiet hours"))
        XCTAssertEqual(decide(.deferred, usage, at: at(26, 23)), .now)
        // A window with no reset time is live for its length after it was seen.
        usage = UsageState(windows: ["five_hour": UsageWindow(type: "five_hour", utilization: 0.9, resetsAt: nil, seen: at(26, 11))])
        XCTAssertEqual(decide(.normal, usage, at: monday), .wait(until: nil, reason: "Paused for usage"))
        // An expired window is ignored.
        usage.record([UsageWindow(type: "five_hour", utilization: 0.99, resetsAt: at(26, 11), seen: monday)])
        XCTAssertEqual(decide(.normal, usage, at: monday), .now)
    }

    func testUsageStateSavesAndNewestWins() throws {
        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-usage-\(UUID().uuidString)", env: [:])
        var state = UsageState()
        state.record([UsageWindow(type: "five_hour", utilization: 0.5, resetsAt: nil, seen: at(26, 12))])
        state.record([UsageWindow(type: "five_hour", utilization: 0.2, resetsAt: nil, seen: at(26, 11))])
        XCTAssertEqual(state.windows["five_hour"]?.utilization, 0.5)
        try state.save(paths)
        XCTAssertEqual(UsageState.load(paths), state)
    }

    // MARK: Push guard

    func testPushGuardParsesTwoFileDiffWithDeletion() {
        let diff = """
        diff --git a/src/a.swift b/src/a.swift
        index 1111..2222 100644
        --- a/src/a.swift
        +++ b/src/a.swift
        @@ -2 +2,2 @@
        -let x = 1
        +let x = 2
        +let y = 3
        diff --git a/old/gone.swift b/old/gone.swift
        deleted file mode 100644
        index 3333..0000000
        --- a/old/gone.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        --- old comment
        -let z = 0
        """
        XCTAssertEqual(PushGuard.parse(diff: diff), [
            ChangedFile(path: "src/a.swift", status: "M", added: ["let x = 2", "let y = 3"], removed: 1),
            ChangedFile(path: "old/gone.swift", status: "D", added: [], removed: 2),
        ])
    }

    func testPushGuardRefusesEachCaseAndPassesClean() {
        func file(_ path: String, status: String = "M", added: [String] = ["let a = 1"], removed: Int = 0) -> ChangedFile {
            ChangedFile(path: path, status: status, added: added, removed: removed)
        }
        XCTAssertEqual(PushGuard.refusal([], maxLines: 400), "Empty change")
        XCTAssertEqual(PushGuard.refusal([file(".github/workflows/ci.yml")], maxLines: 400), "Touches .github/workflows/ci.yml")
        XCTAssertEqual(PushGuard.refusal([file("config/.env.local")], maxLines: 400), "Touches config/.env.local")
        XCTAssertEqual(PushGuard.refusal([file("certs/server.pem")], maxLines: 400), "Touches certs/server.pem")
        XCTAssertEqual(PushGuard.refusal([file("Tests/FooTests.swift", status: "D", added: [], removed: 9)], maxLines: 400),
                       "Deletes test file Tests/FooTests.swift")
        XCTAssertEqual(PushGuard.refusal([file("src/a.test.ts", added: ["it.todo(\"later\")"])], maxLines: 400),
                       "Skips a test in src/a.test.ts")
        XCTAssertEqual(PushGuard.refusal([file("src/a.swift", added: ["  xit(\"x\") {"])], maxLines: 400),
                       "Skips a test in src/a.swift")
        XCTAssertEqual(PushGuard.refusal([file("src/big.swift", added: Array(repeating: "x", count: 8), removed: 3)], maxLines: 10),
                       "11 changed lines, over max_fix_lines 10")
        // Clean passes: exit( is not xit(, and 0 means no line cap.
        XCTAssertNil(PushGuard.refusal([file("src/a.swift", added: ["exit(1)"], removed: 1)], maxLines: 10))
        XCTAssertNil(PushGuard.refusal([file("src/a.swift", added: Array(repeating: "x", count: 900))], maxLines: 0))
    }

    func testIsTestPath() {
        for path in ["Tests/FooTests.swift", "src/app.test.ts", "pkg/test_util.py", "lib/tests/x.rb",
                     "web/__tests__/a.js", "api/_test.go", "spec/models/user.rb"] {
            XCTAssertTrue(PushGuard.isTestPath(path), path)
        }
        for path in ["src/main.swift", "src/testing.swift", "latest/util.py"] {
            XCTAssertFalse(PushGuard.isTestPath(path), path)
        }
    }

    // MARK: Approach

    private func openPR(_ n: Int, branch: String, base: String,
                        checks: [CheckState] = [CheckState(name: "test", status: "COMPLETED", conclusion: "SUCCESS")],
                        approved: Bool = false, clean: Bool = false, draft: Bool = false,
                        requested: [String] = []) -> OpenPR {
        OpenPR(n: n, title: "PR \(n)", url: "https://github.com/acme/api/pull/\(n)", isDraft: draft,
               reviewDecision: approved ? "APPROVED" : nil, mergeStateStatus: clean ? "CLEAN" : "BLOCKED",
               branch: branch, head: "sha\(n)", base: base, checks: checks, requested: requested)
    }

    func testApproachStackSoloAndPhases() {
        let failing = CheckState(name: "lint", status: "COMPLETED", conclusion: "FAILURE")
        let a = openPR(1, branch: "a", base: "main", approved: true, clean: true)
        let b = openPR(2, branch: "b", base: "a", requested: ["alice"])
        let c = openPR(3, branch: "c", base: "b", checks: [failing])
        let d = openPR(4, branch: "d", base: "main", draft: true)

        let lanes = Approach.lanes([d, c, b, a])
        XCTAssertEqual(lanes.map { $0.map(\.n) }, [[1, 2, 3], [4]])

        XCTAssertEqual(Approach.marker(a), 3)
        XCTAssertEqual(Approach.phase(a, state: nil, working: false), .cleared)
        XCTAssertEqual(Approach.label(a, state: nil, working: false), "Ready to land")
        XCTAssertEqual(Approach.marker(b), 1)
        XCTAssertEqual(Approach.phase(b, state: nil, working: false), .waiting)
        XCTAssertEqual(Approach.label(b, state: nil, working: false), "Waiting on alice")
        XCTAssertEqual(Approach.phase(c, state: nil, working: false), .flying)
        XCTAssertEqual(Approach.label(c, state: nil, working: false), "Checks failing · lint")
        XCTAssertEqual(Approach.gates(c, state: nil)[0].who, "Glidepath")
        XCTAssertEqual(Approach.phase(d, state: nil, working: false), .taxiing)

        var planes: [ApproachPlane] = []
        for (li, lane) in lanes.enumerated() {
            for (i, p) in lane.enumerated() {
                planes.append(Approach.plane(p, slug: "acme/api", state: nil, working: false, lane: li,
                                             stackIndex: lane.count > 1 ? i + 1 : nil))
            }
        }
        XCTAssertEqual(planes.map(\.stackIndex), [1, 2, 3, nil])
        XCTAssertEqual(planes.map(\.lane), [0, 0, 0, 1])
        XCTAssertEqual(planes[0].gates.map(\.name), ["CI", "Threads", "Approval", "Ready"])
        XCTAssertEqual(planes[0].ci, "passed")
    }

    func testGateStatesAndWords() {
        func gate(_ pr: OpenPR, _ i: Int, state: TendPR? = nil) -> Gate { Approach.gates(pr, state: state)[i] }
        let pass = CheckState(name: "test", status: "COMPLETED", conclusion: "SUCCESS")
        let skip = CheckState(name: "docs", status: "COMPLETED", conclusion: "SKIPPED")
        let lint = CheckState(name: "lint", status: "COMPLETED", conclusion: "FAILURE")
        let unit = CheckState(name: "unit", status: "COMPLETED", conclusion: "FAILURE")
        let e2e = CheckState(name: "e2e", status: "IN_PROGRESS", conclusion: nil)
        let thread = ReviewThread(id: "t1", isResolved: false,
                                  comments: [ThreadComment(id: "c1", databaseId: nil, author: "gadi", body: "", path: nil, line: nil)])

        // Passed: green counts skipped checks too; threads, approval and readiness all pass.
        let green = openPR(1, branch: "a", base: "main", checks: [pass, skip], approved: true, clean: true)
        XCTAssertEqual(gate(green, 0), Gate(name: "CI", state: .ok, detail: "2 of 2 checks green"))
        XCTAssertEqual(gate(green, 1), Gate(name: "Threads", state: .ok, detail: "All resolved"))
        XCTAssertEqual(gate(green, 2), Gate(name: "Approval", state: .ok, detail: "Approved"))
        XCTAssertEqual(gate(green, 3), Gate(name: "Ready", state: .ok, detail: "No conflicts with main"))

        XCTAssertEqual(gate(openPR(2, branch: "b", base: "main", checks: []), 0), Gate(name: "CI", state: .none, detail: "No checks"))

        // Running: a person is not waiting, so the gate is amber without a name.
        var running = openPR(3, branch: "c", base: "main", checks: [e2e, pass])
        running.mergeStateStatus = "UNSTABLE"
        XCTAssertEqual(gate(running, 0), Gate(name: "CI", state: .wait, detail: "1 running"))
        XCTAssertEqual(gate(running, 3), Gate(name: "Ready", state: .wait, detail: "Checks not all green"))

        // Failing on a PR tend may act on: Glidepath is working, unless the PR is stuck or held.
        let failing = openPR(4, branch: "d", base: "main", checks: [lint, unit, pass])
        XCTAssertEqual(gate(failing, 0), Gate(name: "CI", state: .work, detail: "lint, unit failing", who: "Glidepath"))
        var held = TendPR(slug: "acme/api", n: 4)
        held.held = TendHeld(commit: "abc123", summary: "approved, pushing cancels it", at: at(26, 9))
        XCTAssertEqual(gate(failing, 0, state: held), Gate(name: "CI", state: .wait, detail: "lint, unit failing", who: "you"))
        var stuck = TendPR(slug: "acme/api", n: 4)
        stuck.stuck = "Unit Tests failed twice on this head"
        XCTAssertEqual(gate(failing, 0, state: stuck), Gate(name: "CI", state: .wait, detail: "lint, unit failing", who: "you"))
        var handsOff = failing
        handsOff.labels = [Approach.handsOffLabel]
        XCTAssertEqual(gate(handsOff, 0), Gate(name: "CI", state: .wait, detail: "lint, unit failing", who: "you"))

        // Threads: open ones wait on the reviewer who opened them.
        var threads = openPR(5, branch: "e", base: "main", approved: true, clean: true)
        threads.threads = [thread, ReviewThread(id: "t2", isResolved: false, comments: [])]
        XCTAssertEqual(gate(threads, 1), Gate(name: "Threads", state: .wait, detail: "2 open", who: "gadi"))
        XCTAssertEqual(gate(threads, 1, state: held), Gate(name: "Threads", state: .wait, detail: "2 open", who: "you"))

        // Approval: changes requested name the reviewer; otherwise the requested reviewers, or no review yet.
        var changes = openPR(6, branch: "f", base: "main", requested: ["alice"])
        changes.reviews = [ReviewInfo(id: "r1", author: "gadi", state: "CHANGES_REQUESTED")]
        XCTAssertEqual(gate(changes, 2), Gate(name: "Approval", state: .wait, detail: "Changes requested by gadi", who: "gadi"))
        let asked = openPR(7, branch: "g", base: "main", requested: ["alice", "bob"])
        XCTAssertEqual(gate(asked, 2), Gate(name: "Approval", state: .wait, detail: "Waiting on alice, bob", who: "alice, bob"))
        XCTAssertEqual(gate(openPR(8, branch: "h", base: "main"), 2), Gate(name: "Approval", state: .wait, detail: "No review yet"))

        // Readiness follows mergeStateStatus, and a draft is not reached.
        func ready(_ merge: String, draft: Bool = false, base: String = "main") -> Gate {
            var pr = openPR(9, branch: "i", base: base, draft: draft)
            pr.mergeStateStatus = merge
            return gate(pr, 3)
        }
        XCTAssertEqual(ready("CLEAN", base: "release"), Gate(name: "Ready", state: .ok, detail: "No conflicts with release"))
        XCTAssertEqual(ready("DIRTY"), Gate(name: "Ready", state: .wait, detail: "Conflicts with main"))
        XCTAssertEqual(ready("BEHIND"), Gate(name: "Ready", state: .wait, detail: "Behind main"))
        XCTAssertEqual(ready("BLOCKED"), Gate(name: "Ready", state: .wait, detail: "Blocked by branch rules"))
        XCTAssertEqual(ready("UNSTABLE"), Gate(name: "Ready", state: .wait, detail: "Checks not all green"))
        XCTAssertEqual(ready("UNKNOWN"), Gate(name: "Ready", state: .wait, detail: "Waiting on GitHub"))
        XCTAssertEqual(ready("CLEAN", draft: true), Gate(name: "Ready", state: .none, detail: "Draft"))
        XCTAssertEqual(ready("DRAFT"), Gate(name: "Ready", state: .none, detail: "Draft"))
    }

    func testHeldFixIsNeedsItemAndHolds() {
        let a = openPR(1, branch: "a", base: "main", approved: true, clean: true)
        var held = TendPR(slug: "acme/api", n: 1)
        held.held = TendHeld(commit: "abc123", summary: "approved, pushing cancels the approval", at: at(26, 9))
        XCTAssertEqual(Approach.phase(a, state: held, working: false), .holding)
        XCTAssertEqual(Approach.label(a, state: held, working: false), "Fix held · approved, pushing cancels the approval")
        XCTAssertEqual(Approach.needs("acme/api", a, state: held), NeedsItem(
            id: "acme/api#1/held", slug: "acme/api", n: 1, title: "PR 1", kind: "held",
            detail: "Fix held · approved, pushing cancels the approval"))
        XCTAssertNil(Approach.needs("acme/api", a, state: nil))
    }

    func testFingerprintIgnoresCheckOrder() {
        let lint = CheckState(name: "lint", status: "COMPLETED", conclusion: "FAILURE")
        let test = CheckState(name: "test", status: "COMPLETED", conclusion: "SUCCESS")
        let x = openPR(3, branch: "c", base: "b", checks: [lint, test])
        let y = openPR(3, branch: "c", base: "b", checks: [test, lint])
        XCTAssertEqual(Fingerprint.ci(x), Fingerprint.ci(y))
        XCTAssertEqual(Fingerprint.ci(x), "sha3|lint=FAILURE,test=SUCCESS")
        var moved = x
        moved.head = "sha9"
        XCTAssertNotEqual(Fingerprint.ci(x), Fingerprint.ci(moved))
    }

    func testTendDecisionRoundsAndSkips() {
        let failing = CheckState(name: "lint", status: "COMPLETED", conclusion: "FAILURE")
        var red = openPR(3, branch: "c", base: "main", checks: [failing])
        var state = TendPR(slug: "acme/api", n: 3)
        XCTAssertEqual(TendDecision.decide(red, state: state), .round(.normal))
        red.reviewDecision = "APPROVED"
        XCTAssertEqual(TendDecision.decide(red, state: state), .round(.urgent))
        // The same failure, already tried, is not a new round.
        state.fingerprint = Fingerprint.ci(red)
        XCTAssertEqual(TendDecision.decide(red, state: state), .idle)
        state.fingerprint = nil
        state.held = TendHeld(commit: "abc", summary: "x", at: at(26, 9))
        XCTAssertEqual(TendDecision.decide(red, state: state), .idle)
        state.held = nil
        red.labels = [Approach.handsOffLabel]
        XCTAssertEqual(TendDecision.decide(red, state: state), .skip("hands off"))
        red.labels = []
        state.off = true
        XCTAssertEqual(TendDecision.decide(red, state: state), .skip("hands off"))
        state.off = false
        red.isFork = true
        XCTAssertEqual(TendDecision.decide(red, state: state), .skip("fork"))
        red.isFork = false
        red.checks = [CheckState(name: "lint", status: "IN_PROGRESS", conclusion: nil)]
        XCTAssertEqual(TendDecision.decide(red, state: state), .idle)

        var stuck = TendPR(slug: "acme/api", n: 3)
        stuck.fingerprint = "sha3|lint=FAILURE"
        XCTAssertFalse(TendDecision.clearsStuck(red, state: stuck))
        XCTAssertTrue(TendDecision.clearsStuck(openPR(9, branch: "c", base: "b"), state: stuck))
    }

    // MARK: Tend state

    func testTendLimitsRollDayAndBlock() {
        var s = TendPR(slug: "acme/api", n: 3)
        let cfg = TendConfig()
        TendLimits.rollDay(&s, at(26, 9), calendar: utc)
        s.roundsToday = 5
        XCTAssertEqual(TendLimits.blocked(s, head: "h", cfg), "5 rounds a day reached")
        TendLimits.rollDay(&s, at(26, 20), calendar: utc)
        XCTAssertEqual(s.roundsToday, 5)
        TendLimits.rollDay(&s, at(27, 8), calendar: utc)
        XCTAssertEqual(s.roundsToday, 0)
        s.triesByHead["h"] = 2
        XCTAssertEqual(TendLimits.blocked(s, head: "h", cfg), "2 tries on this head used")
        XCTAssertNil(TendLimits.blocked(s, head: "new", cfg))
    }

    func testCIEvidenceIdsAndWindows() {
        XCTAssertEqual(CIEvidence.ids("https://github.com/acme/api/actions/runs/123/job/456")?.run, 123)
        XCTAssertEqual(CIEvidence.ids("https://github.com/acme/api/actions/runs/123/job/456")?.job, 456)
        XCTAssertNil(CIEvidence.ids("https://github.com/acme/api/actions/runs/9")?.job)
        XCTAssertNil(CIEvidence.ids(nil))

        var lines = (0..<1000).map { "line \($0)" }
        lines[100] = "x ##[error]"
        lines[150] = "y ##[error]"
        // Windows 40...120 and 90...170 overlap, so they merge into 40...170.
        let merged = CIEvidence.windows(lines.joined(separator: "\n"))
        XCTAssertEqual(merged.count, 131)
        XCTAssertEqual(merged.first, "line 40")
        XCTAssertEqual(merged.last, "line 170")
        XCTAssertEqual(CIEvidence.windows(lines.joined(separator: "\n"), cap: 50).count, 50)
        // No error: the last 300 lines.
        let quiet = (0..<500).map { "line \($0)" }.joined(separator: "\n")
        let tail = CIEvidence.windows(quiet)
        XCTAssertEqual(tail.count, 300)
        XCTAssertEqual(tail.first, "line 200")
    }

    func testAutopilotTable() {
        for autopilot in [false, true] {
            for action in [TendAction.giveUp, .flagPaths, .limitHit, .guardRefused] {
                XCTAssertEqual(Autopilot.actor(action, autopilot: autopilot, push: .always), .you)
            }
            XCTAssertEqual(Autopilot.actor(.rerun, autopilot: autopilot, push: .untilApproved), .act)
            XCTAssertEqual(Autopilot.actor(.pushFix(approved: false), autopilot: autopilot, push: .untilApproved), .act)
        }
        XCTAssertEqual(Autopilot.actor(.pushFix(approved: true), autopilot: false, push: .untilApproved), .you)
        XCTAssertEqual(Autopilot.actor(.pushFix(approved: true), autopilot: true, push: .untilApproved), .act)
        XCTAssertEqual(Autopilot.actor(.pushFix(approved: true), autopilot: false, push: .always), .act)
    }

    func testTendStoreRoundTripsAndTowerIsNewestFirst() throws {
        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-tend-\(UUID().uuidString)", env: [:])
        let store = TendStore(paths: paths)
        var s = TendPR(slug: "acme/api", n: 7)
        s.held = TendHeld(commit: "abc", summary: "approved", at: at(26, 9))
        try store.save(s)
        XCTAssertEqual(store.load("acme/api", 7), s)
        XCTAssertEqual(store.all(), [s])
        XCTAssertTrue(store.file("acme/api", 7).hasSuffix("/tend/acme-api-7.json"))
        // A state file from before the newer keys still loads.
        XCTAssertEqual(try RunStore.decoder().decode(TendPR.self, from: Data(#"{"slug":"acme/api","n":4}"#.utf8)),
                       TendPR(slug: "acme/api", n: 4))

        for i in 0..<3 {
            try store.appendTower(TowerLine(at: at(26, 9 + i), slug: "acme/api", n: 7, text: "line \(i)", detail: nil, amber: false))
        }
        XCTAssertEqual(store.tower(limit: 2).map(\.text), ["line 2", "line 1"])
        XCTAssertEqual(store.tower(limit: 10).count, 3)
    }

    // MARK: Playbook

    func testPlaybookRoundTripVerifyAndCap() throws {
        var pb = Playbook().teach("Run swift test before pushing", source: "PR 12", date: at(20, 0))
        pb = pb.verify(["swift test", "swift build"], date: at(21, 0)).verify(["swift test"], date: at(22, 0))
        XCTAssertEqual(pb.commands.first { $0.command == "swift test" }?.verified, 2)
        XCTAssertEqual(pb.commands.first { $0.command == "swift test" }?.date, at(22, 0))
        let text = pb.render()
        XCTAssertTrue(text.contains("- `swift test` · verified 2× · 2026-10-22\n"))
        XCTAssertTrue(text.contains("- Run swift test before pushing · PR 12 · 2026-10-20\n"))
        XCTAssertEqual(Playbook.parse(text), pb)

        // Three long lessons; the first taught is the newest, so the oldest by date is "PR 2".
        var big = Playbook()
        for i in 0..<3 {
            big = big.teach(String(repeating: "lesson \(i) ", count: 100), source: "PR \(i)", date: at(22 - i, 0))
        }
        let capped = big.cap(big.render().count - 1)
        XCTAssertEqual(capped.lessons.map(\.source), ["PR 0", "PR 1"])
        XCTAssertEqual(capped.commands, big.commands)

        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-playbook-\(UUID().uuidString)", env: [:])
        try pb.save("acme/api", paths: paths)
        XCTAssertEqual(Playbook.load("acme/api", paths: paths), pb)
        XCTAssertEqual(Playbook.load("acme/none", paths: paths), Playbook())
    }

    func testPushGuardTakesPathsFromHeaderLines() {
        let diff = """
        diff --git a/docs/a b/c.md b/docs/a b/c.md
        index 1111..2222 100644
        --- a/docs/a b/c.md
        +++ b/docs/a b/c.md
        @@ -1 +1 @@
        -old
        +new
        diff --git a/with space.md b/with space.md
        --- a/with space.md\t
        +++ b/with space.md\t
        @@ -1 +1 @@
        -x
        +y
        diff --git a/old/gone.swift b/old/gone.swift
        deleted file mode 100644
        index 3333..0000000
        --- a/old/gone.swift
        +++ /dev/null
        @@ -1 +0,0 @@
        -let z = 0
        """
        XCTAssertEqual(PushGuard.parse(diff: diff).map(\.path), ["docs/a b/c.md", "with space.md", "old/gone.swift"])
    }

    // MARK: Commit message and playbook commands

    func testCommitMessageDropsAttributionLines() {
        XCTAssertEqual(Tender.cleanCommitMessage("Import the CSV writer\n\nCo-Authored-By: Claude <x@y>\nclaude-session: 123\n🤖 Generated with [Claude Code]\n"),
                       "Import the CSV writer")
        XCTAssertEqual(Tender.cleanCommitMessage("Fix\n\nCO-AUTHORED-BY : someone"), "Fix")
        XCTAssertEqual(Tender.cleanCommitMessage("  Co-Authored-By: a\n  Generated with x  "), "")
        XCTAssertEqual(Tender.cleanCommitMessage("Keep the claude-session note: see docs"), "Keep the claude-session note: see docs")
    }

    func testPlaybookSanitizesCommands() {
        XCTAssertEqual(Playbook.sanitize("  `npm test`  \nrm -rf /"), "npm test")
        XCTAssertNil(Playbook.sanitize(" `` "))
        XCTAssertNil(Playbook.sanitize(""))
        XCTAssertEqual(Playbook.sanitize(String(repeating: "a", count: 300))?.count, 200)
        let pb = Playbook().verify(["swift test\nnoise", "``", "swift test"], date: at(22, 0))
        XCTAssertEqual(pb.commands, [Playbook.Command(command: "swift test", verified: 2, date: at(22, 0))])
    }

    // MARK: Approval, state and evidence

    func testApprovedReadsDecisionOrLatestReviews() {
        func pr(_ decision: String?, _ reviews: [(String, String)]) -> OpenPR {
            var p = openPR(1, branch: "a", base: "main")
            p.reviewDecision = decision
            p.reviews = reviews.enumerated().map { ReviewInfo(id: "R\($0.offset)", author: $0.element.0, state: $0.element.1) }
            return p
        }
        XCTAssertTrue(pr("APPROVED", []).approved)
        XCTAssertFalse(pr("REVIEW_REQUIRED", [("a", "APPROVED")]).approved)
        XCTAssertTrue(pr(nil, [("a", "APPROVED")]).approved)
        // Bob's later approval replaces his change request.
        XCTAssertTrue(pr(nil, [("bob", "CHANGES_REQUESTED"), ("a", "APPROVED"), ("bob", "APPROVED")]).approved)
        XCTAssertFalse(pr(nil, [("a", "APPROVED"), ("bob", "CHANGES_REQUESTED")]).approved)
        XCTAssertFalse(pr(nil, [("a", "COMMENTED")]).approved)
        XCTAssertFalse(pr(nil, []).approved)
    }

    func testPatchPlaneOffChangesOnlyThatPlane() throws {
        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-off-\(UUID().uuidString)", env: [:])
        let store = TendStore(paths: paths)
        let a = Approach.plane(openPR(1, branch: "a", base: "main"), slug: "acme/api", state: nil, working: false,
                               lane: 0, stackIndex: nil)
        let b = Approach.plane(openPR(2, branch: "b", base: "main"), slug: "acme/api", state: nil, working: false,
                               lane: 1, stackIndex: nil)
        try store.saveApproach(ApproachSnapshot(updated: at(26, 9), planes: [a, b], needs: [], queued: 0, status: nil,
                                                working: nil, nextLook: nil))
        store.patchPlaneOff("acme/api", 2, true)
        XCTAssertEqual(store.loadApproach()?.planes.map(\.off), [false, true])
        store.patchPlaneOff("acme/api", 9, true)
        XCTAssertEqual(store.loadApproach()?.planes.map(\.off), [false, true])
    }

    func testRunStoreLoadsOneDayByIdPrefix() throws {
        let paths = Paths(home: NSTemporaryDirectory() + "glidepath-prefix-\(UUID().uuidString)", env: [:])
        let store = RunStore(paths: paths)
        try store.save(RunState.new(id: "20261026-090000-aaaaaa", now: at(26, 9)))
        try store.save(RunState.new(id: "20261025-090000-bbbbbb", now: at(25, 9)))
        XCTAssertEqual(store.loadAll(prefix: "20261026").map(\.id), ["20261026-090000-aaaaaa"])
        XCTAssertEqual(store.loadAll(prefix: "202610").count, 2)
        XCTAssertEqual(store.loadAll().count, 2)
    }

    func testCIEvidenceStripsColourCodes() {
        let windows = CIEvidence.windows("\u{1B}[31m##[error]boom\u{1B}[0m")
        XCTAssertTrue(windows.contains { $0.contains("##[error]boom") })
        XCTAssertFalse(windows.joined().contains("\u{1B}"))
    }
}
