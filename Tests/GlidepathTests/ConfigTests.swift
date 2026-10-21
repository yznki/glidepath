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
            "typo = 1\n",
            "[limits]\nmax_prs_per_run = 0\n",
            "[limits]\nmystery = 1\n",
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
}
