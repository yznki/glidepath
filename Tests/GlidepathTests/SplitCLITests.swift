import XCTest
@testable import Glidepath

final class SplitCLITests: XCTestCase {
    private func part(_ title: String, _ files: [String]) -> SplitPart {
        SplitPart(title: title, why: "", files: files, dependsOn: nil)
    }

    private func flag(_ args: [String], _ name: String) -> String? {
        args.firstIndex(of: name).flatMap { i in i + 1 < args.count ? args[i + 1] : nil }
    }

    func testChangedFilesReadNameStatusWithNULSeparators() {
        let text = "M\0Core/A.swift\0D\0Core/Old.swift\0A\0Tests/New.swift\0"
        let changed = Tender.splitChangedFiles(text)
        XCTAssertEqual(changed.map(\.status), ["M", "D", "A"])
        XCTAssertEqual(changed.map(\.path), ["Core/A.swift", "Core/Old.swift", "Tests/New.swift"])
    }

    func testChangedFilesKeepSpacesAndBracketsInPaths() {
        let text = "M\0Core/my file [1].swift\0D\0Old [x]\tname.swift\0"
        let changed = Tender.splitChangedFiles(text)
        XCTAssertEqual(changed.map(\.path), ["Core/my file [1].swift", "Old [x]\tname.swift"])
        XCTAssertEqual(Tender.splitPartFiles(changed: changed, part: part("One", ["Core/my file [1].swift"])).checkout,
                       ["Core/my file [1].swift"])
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

    func testCheckLineRunsTheCommandUnderShWithItsLogAndExitFile() {
        XCTAssertEqual(Tender.splitCheckLine("npm test", scratch: "/tmp/s", part: 2, index: 1),
                       "sh -c 'npm test' > '/tmp/s/check-2-1.log' 2>&1; echo $? > '/tmp/s/check-2-1.exit'")
    }

    func testCheckLineQuotesSingleQuotesInTheCommand() {
        XCTAssertEqual(Tender.splitCheckLine("grep 'x' a.swift", scratch: "/tmp/s", part: 1, index: 3),
                       "sh -c 'grep '\\''x'\\'' a.swift' > '/tmp/s/check-1-3.log' 2>&1; echo $? > '/tmp/s/check-1-3.exit'")
    }

    /// A temporary folder with the exit files written for the given part: one entry per command, nil for none.
    private func exitFolder(_ codes: [String?]) throws -> String {
        let dir = NSTemporaryDirectory() + "glidepath-exit-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (i, code) in codes.enumerated() {
            guard let code else { continue }
            try (code + "\n").write(toFile: dir + "/check-2-\(i + 1).exit", atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testExitCodesPassWhenEveryCommandExitedZero() throws {
        let dir = try exitFolder(["0", "0"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let result = Tender.splitExitCodes(dir: dir, part: 2, count: 2)
        XCTAssertTrue(result.ok)
        XCTAssertNil(result.failed)
    }

    func testExitCodesNameTheFirstNonZeroOrMissingCommand() throws {
        let dir = try exitFolder(["0", "1", "0"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(Tender.splitExitCodes(dir: dir, part: 2, count: 3).failed, 2)
        let missing = try exitFolder(["0", nil])
        defer { try? FileManager.default.removeItem(atPath: missing) }
        XCTAssertEqual(Tender.splitExitCodes(dir: missing, part: 2, count: 2).failed, 2)
        XCTAssertEqual(Tender.splitExitCodes(dir: missing, part: 3, count: 1).failed, 1)
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
