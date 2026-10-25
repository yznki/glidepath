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
}
