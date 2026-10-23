import XCTest
@testable import Glidepath

final class ConfigEditTests: XCTestCase {
    let home = "/fake/home"

    private func base() throws -> Config {
        try Config.parse("""
        schedule = ["07:00"]

        [[repo]]
        slug = "lumen/api"
        clone = "/fake/home/clones/api"

        [[repo]]
        slug = "lumen/web"
        clone = "/fake/home/clones/web"
        """, home: home)
    }

    /// Every edit must survive render and parse unchanged, or the next load would silently undo it.
    private func assertRoundTrips(_ config: Config, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Config.parse(config.render(), home: home), config, file: file, line: line)
    }

    private func repo(_ config: Config, _ slug: String = "lumen/api") -> RepoConfig {
        config.repos.first { $0.slug == slug }!
    }

    // MARK: Edits round-trip

    func testPostingRoundTrips() throws {
        let c = try ConfigEditor.setPosting(base(), slug: "lumen/api", .draft)
        XCTAssertEqual(repo(c).posting, .draft)
        try assertRoundTrips(c)
    }

    func testAuthorsRoundTrip() throws {
        var c = try ConfigEditor.setAuthors(base(), slug: "lumen/api", .anyone)
        XCTAssertEqual(repo(c).authors, .anyone)
        try assertRoundTrips(c)
        c = try ConfigEditor.setAuthors(c, slug: "lumen/api", .logins(["alice", "bob-2"]))
        XCTAssertEqual(repo(c).authors, .logins(["alice", "bob-2"]))
        try assertRoundTrips(c)
    }

    func testRulesAndModeRoundTrip() throws {
        var c = try ConfigEditor.setRules(base(), slug: "lumen/api", path: "/fake/home/.config/glidepath/rules/lumen-api.md")
        try assertRoundTrips(c)
        c = try ConfigEditor.setRulesMode(c, slug: "lumen/api", .replace)
        XCTAssertEqual(repo(c).rulesMode, .replace)
        try assertRoundTrips(c)
        c = try ConfigEditor.setRules(c, slug: "lumen/api", path: nil)
        try assertRoundTrips(c)
    }

    func testRulesModeRoundTripsWithoutRulesFile() throws {
        let c = try ConfigEditor.setRulesMode(base(), slug: "lumen/api", .replace)
        XCTAssertEqual(repo(c).rulesMode, .replace)
        try assertRoundTrips(c)
    }

    func testGitNexusRoundTrips() throws {
        var c = try ConfigEditor.setGitNexus(base(), slug: "lumen/api", .off)
        XCTAssertEqual(repo(c).gitnexus, .off)
        try assertRoundTrips(c)
        c = try ConfigEditor.setGitNexus(c, slug: "lumen/api", .on)
        try assertRoundTrips(c)
    }

    func testFlaggedPathsAndNoteRoundTrip() throws {
        var c = try ConfigEditor.addFlaggedPath(base(), slug: "lumen/api", path: "infra/")
        c = try ConfigEditor.addFlaggedPath(c, slug: "lumen/api", path: ".github/workflows/")
        c = try ConfigEditor.setFlagNote(c, slug: "lumen/api", note: "  Needs a devops approval.  ")
        XCTAssertEqual(repo(c).flagPaths, ["infra/", ".github/workflows/"])
        XCTAssertEqual(repo(c).flagNote, "Needs a devops approval.")
        try assertRoundTrips(c)
        c = try ConfigEditor.removeFlaggedPath(c, slug: "lumen/api", path: "infra/")
        try assertRoundTrips(c)
    }

    func testFlagNoteWithoutPathsRoundTrips() throws {
        let c = try ConfigEditor.setFlagNote(base(), slug: "lumen/api", note: "Custom note")
        try assertRoundTrips(c)
    }

    func testEditsLeaveOtherReposAlone() throws {
        let c = try ConfigEditor.setPosting(base(), slug: "lumen/api", .review)
        XCTAssertEqual(repo(c, "lumen/web"), repo(try base(), "lumen/web"))
    }

    func testRemoveRepo() throws {
        let c = try ConfigEditor.removeRepo(base(), slug: "lumen/api")
        XCTAssertEqual(c.repos.map(\.slug), ["lumen/web"])
        try assertRoundTrips(c)
        XCTAssertThrowsError(try ConfigEditor.removeRepo(c, slug: "lumen/api"))
    }

    func testAddRepoAndRejectDuplicate() throws {
        let new = RepoConfig(slug: "lumen/cli", clone: ConfigEditor.defaultClone(slug: "lumen/cli", home: home))
        let c = try ConfigEditor.addRepo(base(), new)
        XCTAssertEqual(c.repos.map(\.slug), ["lumen/api", "lumen/web", "lumen/cli"])
        try assertRoundTrips(c)

        let duplicate = RepoConfig(slug: "lumen/api", clone: "/fake/home/clones/api")
        XCTAssertThrowsError(try ConfigEditor.addRepo(c, duplicate)) { error in
            XCTAssertEqual(error as? ConfigError, ConfigError(message: "lumen/api is already in the config"))
        }
    }

    // MARK: Validation rejects bad input and leaves the value unchanged

    func testBadSlugRejectedOnAdd() throws {
        for slug in ["lumen", "lumen/", "/api", "lumen/api/x", "lumen/a b", "lumen/ä"] {
            XCTAssertThrowsError(try ConfigEditor.addRepo(base(), RepoConfig(slug: slug, clone: "/fake/home/x")), slug)
        }
    }

    func testBotLoginsAreValidAndHyphenStartIsNot() throws {
        XCTAssertEqual(try ConfigEditor.validateLogin("renovate[bot]"), "renovate[bot]")
        XCTAssertThrowsError(try ConfigEditor.validateLogin("a[b]c"))
        XCTAssertThrowsError(try ConfigEditor.validateLogin("-x"))
        XCTAssertThrowsError(try ConfigEditor.validateLogin("[bot]"))
    }

    /// Only logins being added are checked: an invalid one already in the file does not block an unrelated save.
    func testExistingInvalidLoginDoesNotBlockAnUnrelatedSave() throws {
        var start = try base()
        start.repos[0].authors = .logins(["old_name"])
        let posted = try ConfigEditor.setPosting(start, slug: "lumen/api", .draft)
        XCTAssertEqual(repo(posted).authors, .logins(["old_name"]))
        let dir = NSTemporaryDirectory() + "glidepath-login-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNoThrow(try ConfigEditor.save(posted, paths: Paths(home: home, env: ["GLIDEPATH_CONFIG_FILE": dir + "/config.toml"])))
        XCTAssertNoThrow(try ConfigEditor.setAuthors(start, slug: "lumen/api", .logins(["old_name", "alice"])))
        XCTAssertThrowsError(try ConfigEditor.setAuthors(start, slug: "lumen/api", .logins(["old_name", "-x"])))
    }

    func testBadLoginsRejected() throws {
        let start = try base()
        for login in ["", "bad_name", "has space", String(repeating: "a", count: 40), "a.b"] {
            XCTAssertThrowsError(try ConfigEditor.setAuthors(start, slug: "lumen/api", .logins(["alice", login])), login)
        }
        XCTAssertEqual(try ConfigEditor.validateLogin(String(repeating: "a", count: 39)), String(repeating: "a", count: 39))
        XCTAssertThrowsError(try ConfigEditor.setAuthors(start, slug: "lumen/api", .logins([])))
        XCTAssertEqual(repo(start).authors, .collaborators)
    }

    func testBadFlaggedPathsRejected() throws {
        let start = try base()
        for path in ["", "/etc/", "../secrets", "infra/../../x", "~/infra", "a\nb"] {
            XCTAssertThrowsError(try ConfigEditor.addFlaggedPath(start, slug: "lumen/api", path: path), path)
        }
        let flagged = try ConfigEditor.addFlaggedPath(start, slug: "lumen/api", path: "infra/")
        XCTAssertThrowsError(try ConfigEditor.addFlaggedPath(flagged, slug: "lumen/api", path: "infra/"))
        XCTAssertThrowsError(try ConfigEditor.removeFlaggedPath(flagged, slug: "lumen/api", path: "docs/"))
        XCTAssertEqual(repo(flagged).flagPaths, ["infra/"])
    }

    func testBadRulesPathAndNoteRejected() throws {
        let start = try base()
        XCTAssertThrowsError(try ConfigEditor.setRules(start, slug: "lumen/api", path: "rules/api.md"))
        XCTAssertThrowsError(try ConfigEditor.setRules(start, slug: "lumen/api", path: "/fake/../etc/passwd"))
        XCTAssertNil(repo(start).rules)

        XCTAssertThrowsError(try ConfigEditor.setFlagNote(start, slug: "lumen/api", note: "   "))
        XCTAssertThrowsError(try ConfigEditor.setFlagNote(start, slug: "lumen/api", note: "two\nlines"))
        XCTAssertEqual(repo(start).flagNote, RepoConfig.defaultFlagNote)
    }

    func testGlobalSwitchesRoundTrip() throws {
        let c = ConfigEditor.setCheckUpdates(ConfigEditor.setNotify(try base(), false), false)
        XCTAssertFalse(c.notify)
        XCTAssertFalse(c.checkUpdates)
        try assertRoundTrips(c)
    }

    func testHotkeySwitchRoundTrips() throws {
        let off = ConfigEditor.setHotkey(try base(), .off)
        XCTAssertEqual(off.hotkey, .off)
        try assertRoundTrips(off)
        XCTAssertEqual(ConfigEditor.setHotkey(off, .on).hotkey, .on)
        let custom = ConfigEditor.setHotkey(try base(), .custom("⌃⌥G"))
        try assertRoundTrips(custom)
    }

    func testReviewOptionSettersRoundTrip() throws {
        var c = ConfigEditor.setReviewDrafts(try base(), true)
        c = ConfigEditor.setIncludeBots(c, true)
        c = ConfigEditor.setModel(c, .sonnet)
        c = ConfigEditor.setStrictness(c, .exacting)
        c = ConfigEditor.setNotifyChangesOnly(c, true)
        c = ConfigEditor.setNotifySound(c, .tink)
        c = ConfigEditor.setRespectFocus(c, false)
        c = try ConfigEditor.setMonthlyTokens(c, 1_000_000)
        c = ConfigEditor.setPauseAtBudget(c, false)
        c = ConfigEditor.setDryRun(c, true)
        c = try ConfigEditor.setRepoReviewDrafts(c, slug: "lumen/api", true)
        XCTAssertEqual(c.model, .sonnet)
        XCTAssertEqual(c.monthlyTokens, 1_000_000)
        XCTAssertEqual(c.repos[0].reviewDrafts, true)
        XCTAssertNil(c.repos[1].reviewDrafts)
        try assertRoundTrips(c)
    }

    func testRepoDraftsCanInheritAgain() throws {
        let c = try ConfigEditor.setRepoReviewDrafts(try ConfigEditor.setRepoReviewDrafts(base(), slug: "lumen/api", true),
                                                     slug: "lumen/api", nil)
        XCTAssertNil(c.repos[0].reviewDrafts)
        XCTAssertThrowsError(try ConfigEditor.setRepoReviewDrafts(base(), slug: "nope/none", true))
    }

    func testMonthlyBudgetRefusesNegative() throws {
        XCTAssertThrowsError(try ConfigEditor.setMonthlyTokens(base(), -1))
        XCTAssertEqual(try ConfigEditor.setMonthlyTokens(base(), 0).monthlyTokens, 0)
    }

    func testUnknownRepoRejected() throws {
        XCTAssertThrowsError(try ConfigEditor.setPosting(base(), slug: "nope/none", .review))
    }

    // MARK: Save

    func testSaveWritesReadableFileKeepingMode() throws {
        let dir = NSTemporaryDirectory() + "glidepath-edit-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let env = ["GLIDEPATH_CONFIG_FILE": dir + "/glidepath/config.toml"]
        let paths = Paths(home: dir, env: env)
        let c = try ConfigEditor.setPosting(base(), slug: "lumen/api", .draft)

        try ConfigEditor.save(c, paths: paths)
        XCTAssertEqual(try Config.load(paths), c)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.configFile)
        try ConfigEditor.save(c, paths: paths)
        let mode = try FileManager.default.attributesOfItem(atPath: paths.configFile)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: (paths.configFile as NSString).deletingLastPathComponent)
        XCTAssertEqual(leftovers, ["config.toml"])
    }
}
