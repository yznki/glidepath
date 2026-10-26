import XCTest
@testable import Glidepath

final class SplitCLITests: XCTestCase {
    private func part(_ title: String, _ files: [String]) -> SplitPart {
        SplitPart(title: title, why: "", files: files, dependsOn: nil)
    }

    private func flag(_ args: [String], _ name: String) -> String? {
        args.firstIndex(of: name).flatMap { i in i + 1 < args.count ? args[i + 1] : nil }
    }

    func testChangedFilesReadNameStatus() {
        let text = "M\tCore/A.swift\nD\tCore/Old.swift\nA\tTests/New.swift\n"
        let changed = Tender.splitChangedFiles(text)
        XCTAssertEqual(changed.map(\.status), ["M", "D", "A"])
        XCTAssertEqual(changed.map(\.path), ["Core/A.swift", "Core/Old.swift", "Tests/New.swift"])
    }

    func testPartFilesSplitCheckoutFromRemoval() {
        let changed: [(status: Character, path: String)] = [
            (status: "M", path: "Core/A.swift"), (status: "D", path: "Core/Old.swift"), (status: "A", path: "Tests/B.swift"),
        ]
        let part = part("Types", ["Core/Old.swift", "Core/A.swift"])
        let files = Tender.splitPartFiles(changed: changed, part: part)
        XCTAssertEqual(files.checkout, ["Core/A.swift"])
        XCTAssertEqual(files.remove, ["Core/Old.swift"])
    }

    func testPartFilesIgnoreFilesOfOtherParts() {
        let changed: [(status: Character, path: String)] = [(status: "M", path: "Core/A.swift"), (status: "M", path: "Core/B.swift")]
        let files = Tender.splitPartFiles(changed: changed, part: part("B", ["Core/B.swift"]))
        XCTAssertEqual(files.checkout, ["Core/B.swift"])
        XCTAssertEqual(files.remove, [])
    }

    func testCheckResultReadsTheLastJSONLine() {
        let text = "running npm test\n{\"ok\":false,\"failed\":\"npm test\",\"tail\":\"1 failing\"}\n"
        let result = Tender.splitCheckResult(text)
        XCTAssertEqual(result?.ok, false)
        XCTAssertEqual(result?.failed, "npm test")
    }

    func testCheckResultPassesWithNoFailure() {
        let result = Tender.splitCheckResult("{\"ok\":true,\"failed\":\"\",\"tail\":\"\"}")
        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(result?.failed, "")
    }

    func testCheckResultIsNilWhenNoLineReads() {
        XCTAssertNil(Tender.splitCheckResult("the tests look fine to me"))
        XCTAssertNil(Tender.splitCheckResult("{\"ok\": maybe}"))
    }

    func testCommentLinksTheStackInOrder() {
        XCTAssertEqual(Tender.splitComment(prs: [1301, 1302, 1303]), "Split into #1301 → #1302 → #1303.")
    }

    func testPlanArgumentsAreReadOnlyOpusOnHighEffortUnderTheSandbox() {
        let config = Config(schedule: [], limits: Limits(), repos: [])
        let args = Tender.splitPlanArguments(prompt: "plan", system: "skill", scratch: "/tmp/s", worktree: "/tmp/wt",
                                             config: config)
        XCTAssertEqual(flag(args, "--tools"), "Read,Grep,Glob")
        XCTAssertEqual(flag(args, "--model"), "opus")
        XCTAssertEqual(flag(args, "--effort"), "high")
        XCTAssertEqual(flag(args, "--max-budget-usd"), String(config.tend.maxUsdPerSession))
        XCTAssertFalse(args.contains("--advisor"))
        XCTAssertEqual(flag(args, "--output-format"), "stream-json")
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertNotNil(flag(args, "--settings"))
    }

    func testCheckArgumentsAreBashOnlyHaikuOnLowEffort() {
        let config = Config(schedule: [], limits: Limits(), repos: [])
        let args = Tender.splitCheckArguments(prompt: "run", scratch: "/tmp/s", config: config)
        XCTAssertEqual(flag(args, "--tools"), "Bash")
        XCTAssertEqual(flag(args, "--model"), "haiku")
        XCTAssertEqual(flag(args, "--effort"), "low")
        XCTAssertEqual(flag(args, "--max-budget-usd"), "1")
        XCTAssertEqual(flag(args, "--permission-mode"), "dontAsk")
        XCTAssertNotNil(flag(args, "--settings"))
    }
}
