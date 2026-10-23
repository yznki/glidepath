import XCTest
@testable import Glidepath

final class ConfigTests: XCTestCase {
    let home = "/fake/home"

    func testFullConfigParses() throws {
        let text = """
        schedule = ["07:00", "19:30"]

        [limits]
        max_prs_per_run = 4
        max_changed_lines = 2000
        split_over_lines = 800

        [[repo]]
        slug = "acme/api"
        clone = "~/clones/api"
        posting = "review"
        authors = ["alice", "bob"]
        rules = "~/rules/api.md"
        rules_mode = "replace"
        gitnexus = "off"
        """
        let c = try Config.parse(text, home: home)
        XCTAssertEqual(c.schedule, [ScheduleTime("07:00")!, ScheduleTime("19:30")!])
        XCTAssertEqual(c.limits, Limits(maxPRsPerRun: 4, maxChangedLines: 2000, splitOverLines: 800))
        XCTAssertEqual(c.repos.count, 1)
        let r = c.repos[0]
        XCTAssertEqual(r.slug, "acme/api")
        XCTAssertEqual(r.clone, "/fake/home/clones/api")
        XCTAssertEqual(r.posting, .review)
        XCTAssertEqual(r.authors, .logins(["alice", "bob"]))
        XCTAssertEqual(r.rules, "/fake/home/rules/api.md")
        XCTAssertEqual(r.rulesMode, .replace)
        XCTAssertEqual(r.gitnexus, .off)
    }

    func testCheckUpdatesDefaultsOnAndParses() throws {
        XCTAssertTrue(try Config.parse("schedule = [\"07:00\"]\n", home: home).checkUpdates)
        XCTAssertFalse(try Config.parse("check_updates = false\n", home: home).checkUpdates)
        XCTAssertThrowsError(try Config.parse("check_updates = \"no\"\n", home: home))
    }

    func testEmptyConfigStillMeansOpusAndTen() throws {
        let c = try Config.parse("schedule = [\"07:00\"]\n", home: home)
        XCTAssertEqual(c.model, .opus)
        XCTAssertEqual(c.limits.maxPRsPerRun, 10)
    }

    func testRepoWithoutPostingStillMeansComment() throws {
        let c = try Config.parse("[[repo]]\nslug = \"acme/old\"\n", home: home)
        XCTAssertEqual(c.repos[0].posting, .comment)
    }

    func testDefaults() throws {
        let c = try Config.parse("[[repo]]\nslug = \"acme/web\"\n", home: home)
        XCTAssertEqual(c.schedule.map(\.text), ["07:00", "13:00", "19:00"])
        XCTAssertEqual(c.limits, Limits())
        let r = c.repos[0]
        XCTAssertEqual(r.clone, "/fake/home/glidepath/clones/acme-web")
        XCTAssertEqual(r.posting, .comment)
        XCTAssertEqual(r.authors, .collaborators)
        XCTAssertEqual(r.rules, nil)
        XCTAssertEqual(r.rulesMode, .extend)
        XCTAssertEqual(r.gitnexus, .auto)
    }

    func testRejectsBadValues() {
        let bad = [
            "schedule = [\"7am\"]\n",
            "schedule = []\n",
            "[limits]\nmax_prs_per_run = 0\n",
            "[[repo]]\nslug = \"no-slash\"\n",
            "[[repo]]\nslug = \"a/b\"\nposting = \"merge\"\n",
            "[[repo]]\nslug = \"a/b\"\ngitnexus = \"maybe\"\n",
            "[[repo]]\nslug = \"a/b\"\nauthors = \"everyone\"\n",
            "[[repo]]\nslug = \"a/b\"\nauthors = []\n",
            "[[repo]]\nslug = \"a/b\"\n[[repo]]\nslug = \"a/b\"\n",
            "[[repo]]\nclone = \"/x\"\n",
            "[[repo]]\nslug = \"a/b\"\nrules_mode = \"merge\"\n",
        ]
        for text in bad {
            XCTAssertThrowsError(try Config.parse(text, home: home), text)
        }
    }

    func testRenderRoundTrips() throws {
        let original = try Config.parse("""
        schedule = ["09:05"]
        [limits]
        max_prs_per_run = 2
        [[repo]]
        slug = "acme/api"
        authors = ["alice"]
        rules = "/abs/rules.md"
        [[repo]]
        slug = "acme/web"
        posting = "review"
        """, home: home)
        let again = try Config.parse(original.render(), home: home)
        XCTAssertEqual(again, original)
    }

    func testUnknownKeysAreKeptAndRoundTrip() throws {
        let text = """
        typo = 1
        future = { on = true, tags = ["a", "b"] }
        schedule = ["07:00"]
        [limits]
        mystery = "x"
        [[repo]]
        slug = "a/b"
        extra_repo_key = [1, 2]
        [section]
        name = "s"
        [[items]]
        n = 1
        """
        let c = try Config.parse(text, home: home)
        XCTAssertEqual(c.extras["typo"], .int(1))
        XCTAssertEqual(c.extras["future"], .table(["on": .bool(true), "tags": .array([.string("a"), .string("b")])]))
        XCTAssertEqual(c.extras["section"], .table(["name": .string("s")]))
        XCTAssertEqual(c.extras["items"], .array([.table(["n": .int(1)])]))
        XCTAssertEqual(c.limits.extras["mystery"], .string("x"))
        XCTAssertEqual(c.repos[0].extras["extra_repo_key"], .array([.int(1), .int(2)]))
        XCTAssertEqual(c.unknownKeys, ["future (top level)", "items (top level)", "section (top level)", "typo (top level)",
                                       "mystery in [limits]", "extra_repo_key in repo a/b"])
        XCTAssertEqual(try Config.parse(c.render(), home: home), c)
    }

    func testKnownKeysStayStrictWhenUnknownKeysArePresent() {
        XCTAssertThrowsError(try Config.parse("typo = 1\nnotify = \"yes\"\n", home: home))
        XCTAssertThrowsError(try Config.parse("[limits]\nmystery = 1\nmax_prs_per_run = 0\n", home: home))
    }

    func testScheduleTimeParsing() {
        XCTAssertNotNil(ScheduleTime("00:00"))
        XCTAssertNotNil(ScheduleTime("23:59"))
        XCTAssertNil(ScheduleTime("24:00"))
        XCTAssertNil(ScheduleTime("7:00"))
        XCTAssertNil(ScheduleTime("07:60"))
    }

    func testIncludeOwnDefaultsFalseAndParses() throws {
        XCTAssertFalse(try Config.parse("[[repo]]\nslug = \"a/b\"\n", home: home).repos[0].includeOwn)
        XCTAssertTrue(try Config.parse("[[repo]]\nslug = \"a/b\"\ninclude_own = true\n", home: home).repos[0].includeOwn)
        XCTAssertThrowsError(try Config.parse("[[repo]]\nslug = \"a/b\"\ninclude_own = \"yes\"\n", home: home))
    }

    func testRelativeCloneRejected() {
        XCTAssertThrowsError(try Config.parse("[[repo]]\nslug = \"a/b\"\nclone = \"clones/x\"\n", home: home))
    }

    func testSlugValidation() {
        XCTAssertTrue(RepoConfig.isValidSlug("acme/api.v2"))
        XCTAssertFalse(RepoConfig.isValidSlug("acme"))
        XCTAssertFalse(RepoConfig.isValidSlug("acme/api; rm"))
        XCTAssertFalse(RepoConfig.isValidSlug("../x/y"))
    }

    func testNewKeysParseAndDefault() throws {
        let c = try Config.parse("""
        notify = false
        [[repo]]
        slug = "acme/api"
        posting = "draft"
        gitnexus_refresh = false
        flag_paths = ["infra/", ".github/workflows/"]
        flag_note = "Needs a devops approval."
        """, home: home)
        XCTAssertFalse(c.notify)
        let r = c.repos[0]
        XCTAssertEqual(r.posting, .draft)
        XCTAssertFalse(r.gitnexusRefresh)
        XCTAssertEqual(r.flagPaths, ["infra/", ".github/workflows/"])
        XCTAssertEqual(r.flagNote, "Needs a devops approval.")

        let defaults = try Config.parse("[[repo]]\nslug = \"acme/web\"\n", home: home)
        XCTAssertTrue(defaults.notify)
        XCTAssertTrue(defaults.repos[0].gitnexusRefresh)
        XCTAssertEqual(defaults.repos[0].flagPaths, [])
        XCTAssertEqual(defaults.repos[0].flagNote, RepoConfig.defaultFlagNote)
    }

    func testNewKeysRejectBadValues() {
        for text in ["notify = \"yes\"\n", "[[repo]]\nslug = \"a/b\"\ngitnexus_refresh = 1\n",
                     "[[repo]]\nslug = \"a/b\"\nflag_paths = \"infra/\"\n",
                     "[[repo]]\nslug = \"a/b\"\nflag_paths = [\"\"]\n"] {
            XCTAssertThrowsError(try Config.parse(text, home: home), text)
        }
    }

    func testNewKeysSurviveRender() throws {
        let original = try Config.parse("""
        notify = false
        [[repo]]
        slug = "acme/api"
        posting = "draft"
        gitnexus_refresh = false
        flag_paths = ["infra/"]
        flag_note = "Check infra."
        """, home: home)
        XCTAssertEqual(try Config.parse(original.render(), home: home), original)
    }

    func testHotkeyDefaultsOnAndRoundTrips() throws {
        XCTAssertEqual(try Config.parse("", home: home).hotkey, .on)
        let off = try Config.parse("hotkey = false\n", home: home)
        XCTAssertEqual(off.hotkey, .off)
        XCTAssertEqual(try Config.parse(off.render(), home: home), off)
        XCTAssertThrowsError(try Config.parse("hotkey = \"yes\"\n", home: home))
        // The default is left out, so an older binary that rejects unknown keys still reads the file.
        let on = try Config.parse("", home: home)
        XCTAssertFalse(on.render().contains("hotkey"))
    }

    func testRenderEscapesStringsSoTheyReadBack() throws {
        var repo = RepoConfig(slug: "acme/api", clone: "/tmp/a \"b\" \\c")
        repo.flagPaths = ["infra\\\"x/"]
        repo.flagNote = "Say \"hi\" \\ then\nnext\ttab"
        let config = Config(schedule: Config.defaultSchedule.compactMap(ScheduleTime.init), limits: Limits(), repos: [repo])
        let back = try Config.parse(config.render(), home: home)
        XCTAssertEqual(back.repos[0].clone, repo.clone)
        XCTAssertEqual(back.repos[0].flagPaths, repo.flagPaths)
        XCTAssertEqual(back.repos[0].flagNote, repo.flagNote)
    }

    func testHotkeyAcceptsAShortcutString() throws {
        let custom = try Config.parse("hotkey = \"⌃⌥G\"\n", home: home)
        XCTAssertEqual(custom.hotkey, .custom("⌃⌥G"))
        XCTAssertEqual(try Config.parse(custom.render(), home: home), custom)
        XCTAssertThrowsError(try Config.parse("hotkey = \"G\"\n", home: home), "a key needs a modifier")
        XCTAssertThrowsError(try Config.parse("hotkey = 3\n", home: home))
    }

    func testReviewOptionsParseAndDefault() throws {
        let c = try Config.parse("", home: home)
        XCTAssertFalse(c.reviewDrafts)
        XCTAssertFalse(c.includeBots)
        XCTAssertEqual(c.model, .opus)
        XCTAssertEqual(c.strictness, .balanced)
        XCTAssertEqual(c.notifySound, .glass)
        XCTAssertTrue(c.respectFocus)
        XCTAssertTrue(c.pauseAtBudget)
        XCTAssertEqual(c.monthlyTokens, 0)
        XCTAssertFalse(c.dryRun)
        XCTAssertFalse(c.notifyChangesOnly)

        let set = try Config.parse("""
        review_drafts = true
        include_bots = true
        model = "haiku"
        strictness = "ruthless"
        notify_changes_only = true
        notify_sound = "none"
        respect_focus = false
        monthly_tokens = 5000000
        pause_at_budget = false
        dry_run = true
        """, home: home)
        XCTAssertTrue(set.reviewDrafts)
        XCTAssertTrue(set.includeBots)
        XCTAssertEqual(set.model, .haiku)
        XCTAssertEqual(set.strictness, .ruthless)
        XCTAssertTrue(set.notifyChangesOnly)
        XCTAssertEqual(set.notifySound, .none)
        XCTAssertFalse(set.respectFocus)
        XCTAssertEqual(set.monthlyTokens, 5_000_000)
        XCTAssertFalse(set.pauseAtBudget)
        XCTAssertTrue(set.dryRun)
        XCTAssertEqual(try Config.parse(set.render(), home: home), set)
    }

    func testReviewOptionsRejectBadValues() {
        let bad = [
            "model = \"gpt\"", "model = 4", "strictness = \"strict\"", "notify_sound = \"boom\"",
            "review_drafts = \"yes\"", "include_bots = 1", "monthly_tokens = -1", "monthly_tokens = \"5\"",
            "respect_focus = \"no\"", "dry_run = 0", "pause_at_budget = \"x\"", "notify_changes_only = 2",
        ]
        for line in bad {
            XCTAssertThrowsError(try Config.parse(line + "\n", home: home), line)
        }
    }

    func testDefaultReviewOptionsAreLeftOutOfTheFile() {
        let text = (try? Config.parse("", home: home).render()) ?? ""
        for key in ["review_drafts", "include_bots", "model", "strictness", "notify_sound", "monthly_tokens", "dry_run"] {
            XCTAssertFalse(text.contains(key), key)
        }
    }

    func testRepoReviewDraftsInheritsWhenAbsent() throws {
        let inherit = try Config.parse("[[repo]]\nslug = \"c/d\"\n", home: home).repos[0]
        XCTAssertNil(inherit.reviewDrafts)
        let on = try Config.parse("[[repo]]\nslug = \"a/b\"\nreview_drafts = true\n", home: home).repos[0]
        XCTAssertEqual(on.reviewDrafts, true)
        let off = try Config.parse("[[repo]]\nslug = \"a/b\"\nreview_drafts = false\n", home: home).repos[0]
        XCTAssertEqual(off.reviewDrafts, false)
        let c = Config(schedule: Config.defaultSchedule.compactMap(ScheduleTime.init), limits: Limits(), repos: [off, inherit])
        XCTAssertEqual(try Config.parse(c.render(), home: home), c)
        XCTAssertThrowsError(try Config.parse("[[repo]]\nslug = \"a/b\"\nreview_drafts = 1\n", home: home))
    }

    func testStrictnessLinesAreTheSpecifiedSentences() {
        XCTAssertEqual(Strictness.balanced.promptLine, "")
        XCTAssertEqual(Strictness.relaxed.promptLine, "Let style and small things go; flag only real bugs.")
        XCTAssertEqual(Strictness.easygoing.promptLine, "Flag only what could break.")
        XCTAssertEqual(Strictness.exacting.promptLine, "Also flag naming, missing tests and unhandled edge cases.")
        XCTAssertEqual(Strictness.ruthless.promptLine, "Flag every issue you find, including nits.")
    }

    func testSlugRejectsDotSegments() {
        for slug in ["./x", "x/..", "../x", "a/.", "./.."] {
            XCTAssertFalse(RepoConfig.isValidSlug(slug), slug)
        }
        XCTAssertTrue(RepoConfig.isValidSlug("lumen/api"))
        XCTAssertTrue(RepoConfig.isValidSlug("my.org/web-app_2"))
    }
}
