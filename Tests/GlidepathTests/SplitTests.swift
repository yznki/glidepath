import XCTest
@testable import Glidepath

final class SplitTests: XCTestCase {
    func part(_ title: String, _ files: [String], dependsOn: Int? = nil) -> SplitPart {
        SplitPart(title: title, why: "", files: files, dependsOn: dependsOn)
    }

    let changed = ["Core/A.swift", "Core/B.swift", "Tests/BTests.swift"]

    // MARK: validate

    func testValidateAcceptsEveryChangedFileOnceInOrder() {
        let parts = [part("Types", ["Core/A.swift"]), part("Caller", ["Core/B.swift", "Tests/BTests.swift"], dependsOn: 1)]
        XCTAssertNil(Split.validate(parts, changed: changed))
    }

    func testValidateReportsMissingFile() {
        let parts = [part("One", ["Core/A.swift"]), part("Two", ["Core/B.swift"])]
        XCTAssertEqual(Split.validate(parts, changed: changed), "Tests/BTests.swift is in no part")
    }

    func testValidateReportsDuplicateFile() {
        let parts = [part("One", ["Core/A.swift", "Core/B.swift"]), part("Two", ["Core/B.swift", "Tests/BTests.swift"])]
        XCTAssertEqual(Split.validate(parts, changed: changed), "Core/B.swift is in more than one part")
    }

    func testValidateReportsUnknownFile() {
        let parts = [part("One", ["Core/A.swift", "Core/Z.swift"]), part("Two", ["Core/B.swift", "Tests/BTests.swift"])]
        XCTAssertEqual(Split.validate(parts, changed: changed), "Core/Z.swift is not changed in this PR")
    }

    func testValidateNeedsTwoToSixParts() {
        XCTAssertEqual(Split.validate([part("Only", changed)], changed: changed), "A split has 2 to 6 parts, not 1")
        let seven = (1...7).map { part("P\($0)", ["f\($0).swift"]) }
        XCTAssertEqual(Split.validate(seven, changed: seven.flatMap(\.files)), "A split has 2 to 6 parts, not 7")
    }

    func testValidateRejectsEmptyTitleAndNoFiles() {
        let blank = [part("One", ["Core/A.swift"]), part("  ", ["Core/B.swift", "Tests/BTests.swift"])]
        XCTAssertEqual(Split.validate(blank, changed: changed), "Part 2 has no title")
        let empty = [part("One", ["Core/A.swift", "Core/B.swift", "Tests/BTests.swift"]), part("Two", [])]
        XCTAssertEqual(Split.validate(empty, changed: changed), "Part 2 has no files")
    }

    func testValidateDependsOnMustBeAnEarlierPart() {
        let rest = ["Core/B.swift", "Tests/BTests.swift"]
        XCTAssertEqual(Split.validate([part("One", ["Core/A.swift"], dependsOn: 2), part("Two", rest)], changed: changed),
                       "Part 1 depends on part 2, which is not an earlier part")
        XCTAssertEqual(Split.validate([part("One", ["Core/A.swift"]), part("Two", rest, dependsOn: 2)], changed: changed),
                       "Part 2 depends on part 2, which is not an earlier part")
        XCTAssertEqual(Split.validate([part("One", ["Core/A.swift"]), part("Two", rest, dependsOn: 0)], changed: changed),
                       "Part 2 depends on part 0, which is not an earlier part")
        XCTAssertNil(Split.validate([part("One", ["Core/A.swift"]), part("Two", rest, dependsOn: 1)], changed: changed))
    }

    // MARK: branches

    func testBranchesChainFromTheBase() {
        let plan = Split.branches(branch: "feat", base: "main", count: 3)
        XCTAssertEqual(plan.map(\.branch), ["feat-part-1", "feat-part-2", "feat-part-3"])
        XCTAssertEqual(plan.map(\.base), ["main", "feat-part-1", "feat-part-2"])
        XCTAssertTrue(Split.branches(branch: "feat", base: "main", count: 0).isEmpty)
    }

    // MARK: stackTable

    func testStackTableMarksTheCurrentPart() {
        let parts = [part("Types", []), part("Caller", []), part("Tests", [])]
        XCTAssertEqual(Split.stackTable(parts, prs: [10, 11, 12], current: 2),
                       "1. #10 Types\n2. #11 Caller ← this PR\n3. #12 Tests")
        XCTAssertEqual(Split.stackTable(parts, prs: [], current: 1),
                       "1. (new) Types ← this PR\n2. (new) Caller\n3. (new) Tests")
    }

    // MARK: parse

    func testParseReadsAPlainJSONLine() {
        let text = #"{"parts": [{"title": "Types", "why": "Shared.", "files": ["Core/A.swift"], "depends_on": null}, {"title": "Caller", "why": "", "files": ["Core/B.swift"], "depends_on": 1}]}"#
        XCTAssertEqual(Split.parse(text), [
            SplitPart(title: "Types", why: "Shared.", files: ["Core/A.swift"], dependsOn: nil),
            SplitPart(title: "Caller", why: "", files: ["Core/B.swift"], dependsOn: 1),
        ])
    }

    func testParseTakesTheLastJSONLineAfterProse() {
        let text = "I read the diff.\nThree parts, by file.\n{\"parts\": [{\"title\": \"Only\", \"files\": [\"Core/A.swift\"]}]}\n"
        XCTAssertEqual(Split.parse(text), [SplitPart(title: "Only", why: "", files: ["Core/A.swift"], dependsOn: nil)])
    }

    func testParseReturnsNilForGarbage() {
        XCTAssertNil(Split.parse("I could not split this."))
        XCTAssertNil(Split.parse("{\"parts\": [{\"why\": \"no title\"}]}"))
        XCTAssertNil(Split.parse(""))
    }

    // MARK: due

    func testDueWhenOverTheLimitAndNoPlanYet() {
        let big = OpenPR(n: 12, title: "Big", branch: "feat", head: "sha1", base: "main", additions: 1000, deletions: 600)
        XCTAssertTrue(Split.due(big, plan: nil, overLines: 1500))
        XCTAssertFalse(Split.due(big, plan: nil, overLines: 1600))
    }

    func testNotDueOnceAnyPlanExistsForThePR() {
        let big = OpenPR(n: 12, title: "Big", branch: "feat", head: "sha1", base: "main", additions: 1000, deletions: 600)
        XCTAssertFalse(Split.due(big, plan: plan(head: "sha1", status: "proposed"), overLines: 1500))
        XCTAssertFalse(Split.due(big, plan: plan(head: "old", status: "proposed"), overLines: 1500))
        XCTAssertFalse(Split.due(big, plan: plan(head: "old", status: "kept"), overLines: 1500))
    }

    func testNotDueForAPartBranch() {
        var part = OpenPR(n: 13, title: "Part", branch: "feat-part-2", head: "sha2", base: "feat-part-1",
                          additions: 1000, deletions: 600)
        XCTAssertFalse(Split.due(part, plan: nil, overLines: 1500))
        part.branch = "feat-parts"
        XCTAssertTrue(Split.due(part, plan: nil, overLines: 1500))
    }

    func testStaleAfterTwoHoursWhileRunning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var running = plan(head: "sha1", status: "planning")
        running.at = now.addingTimeInterval(-3600)
        XCTAssertFalse(Split.isStale(running, now: now))
        running.at = now.addingTimeInterval(-3 * 3600)
        XCTAssertTrue(Split.isStale(running, now: now))
        XCTAssertEqual(Split.effective(running, now: now).status, "failed")
        XCTAssertEqual(Split.effective(running, now: now).failed, "Interrupted")
        running.status = "building"
        XCTAssertTrue(Split.isStale(running, now: now))
        running.status = "proposed"
        XCTAssertFalse(Split.isStale(running, now: now))
        XCTAssertEqual(Split.effective(running, now: now), running)
    }

    // MARK: text

    func testValidateLimitsTheTitleAndWhy() {
        var long = part("One", ["Core/A.swift"])
        let rest = [part("Two", ["Core/B.swift", "Tests/BTests.swift"])]
        let titleProblem = "Part 1's title is over 120 characters or has a line break"
        long.title = String(repeating: "t", count: 121)
        XCTAssertEqual(Split.validate([long] + rest, changed: changed), titleProblem)
        long.title = "One\nTwo"
        XCTAssertEqual(Split.validate([long] + rest, changed: changed), titleProblem)
        long.title = "One"
        long.why = String(repeating: "w", count: 501)
        XCTAssertEqual(Split.validate([long] + rest, changed: changed), "Part 1's why is over 500 characters")
        long.why = String(repeating: "w", count: 500)
        XCTAssertNil(Split.validate([long] + rest, changed: changed))
    }

    func testPublicTextRefusesMentionsAndLinks() {
        var parts = [part("Types", ["Core/A.swift"]), part("Caller", ["Core/B.swift", "Tests/BTests.swift"])]
        XCTAssertNil(Split.publicTextRefusal(parts, slug: "acme/api", n: 12))
        parts[1].why = "Thanks @gadi for the review."
        XCTAssertEqual(Split.publicTextRefusal(parts, slug: "acme/api", n: 12),
                       "Part 2 has a mention, a link or markup, which a PR may not carry")
        parts[1].why = "See https://example.com/x"
        XCTAssertNotNil(Split.publicTextRefusal(parts, slug: "acme/api", n: 12))
    }

    func testNotDueForDraftForkOrHandsOff() {
        let base = OpenPR(n: 12, title: "Big", branch: "feat", head: "sha1", base: "main", additions: 1000, deletions: 600)
        var draft = base
        draft.isDraft = true
        XCTAssertFalse(Split.due(draft, plan: nil, overLines: 1500))
        var fork = base
        fork.isFork = true
        XCTAssertFalse(Split.due(fork, plan: nil, overLines: 1500))
        var off = base
        off.labels = [Approach.handsOffLabel]
        XCTAssertFalse(Split.due(off, plan: nil, overLines: 1500))
    }

    // MARK: needs

    func testProposedSplitIsANeedsItem() {
        let pr = OpenPR(n: 12, title: "Big", branch: "feat", head: "sha1", base: "main")
        let items = Approach.needs("acme/api", pr, state: nil, split: plan(head: "sha1", status: "proposed"))
        XCTAssertEqual(items, [NeedsItem(id: "acme/api#12/split", slug: "acme/api", n: 12, title: "Big", kind: "split",
                                         detail: "Split proposed · 3 parts")])
        XCTAssertTrue(Approach.needs("acme/api", pr, state: nil, split: plan(head: "sha1", status: "planning")).isEmpty)
    }

    // MARK: SplitPlan

    func testSplitPlanDecodesWithDefaults() throws {
        let json = """
        {"slug": "acme/api", "n": 12, "head": "sha1", "branch": "feat", "base": "main", "status": "proposed",
         "parts": [{"title": "Types", "files": ["Core/A.swift"], "depends_on": null},
                   {"title": "Caller", "why": "Uses types.", "files": ["Core/B.swift"], "depends_on": 1}],
         "at": "2026-10-26T09:00:00Z"}
        """
        let decoded = try RunStore.decoder().decode(SplitPlan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.parts[1], SplitPart(title: "Caller", why: "Uses types.", files: ["Core/B.swift"], dependsOn: 1))
        XCTAssertEqual(decoded.parts[0].why, "")
        XCTAssertEqual(decoded.prs, [])
        XCTAssertEqual(decoded.checks, [])
        XCTAssertNil(decoded.failed)
        let again = try RunStore.decoder().decode(SplitPlan.self, from: RunStore.encoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }

    // MARK: store

    func testStoreKeepsSplitPlansOutOfAll() throws {
        let dir = NSTemporaryDirectory() + "glidepath-split-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = TendStore(paths: Paths(home: dir, env: ["GLIDEPATH_STATE_DIR": dir + "/state"]))
        let saved = plan(head: "sha1", status: "proposed")
        try store.saveSplit(saved)
        XCTAssertEqual(store.loadSplit("acme/api", 12), saved)
        XCTAssertTrue(store.all().isEmpty)
    }

    private func plan(head: String, status: String) -> SplitPlan {
        SplitPlan(slug: "acme/api", n: 12, head: head, branch: "feat", base: "main",
                  parts: [part("Types", ["Core/A.swift"]), part("Caller", ["Core/B.swift"], dependsOn: 1),
                          part("Tests", ["Tests/BTests.swift"], dependsOn: 2)],
                  status: status, at: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
