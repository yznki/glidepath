import XCTest
@testable import Glidepath

final class PRDiffTests: XCTestCase {
    let head = "abc123"

    func testDiffArgumentsUseLiteralPathspecsAndNoRenames() {
        let args = PRCommands.diffArguments(clone: "/c", n: 7, head: head, path: "app/[id].tsx")
        XCTAssertEqual(args, ["-C", "/c", "--literal-pathspecs", "diff", "--no-color", "--no-ext-diff", "--no-renames",
                              "refs/glidepath/base/7...abc123", "--", "app/[id].tsx"])
        // The option is a git option, so it comes before the subcommand.
        XCTAssertLessThan(args.firstIndex(of: "--literal-pathspecs")!, args.firstIndex(of: "diff")!)
    }

    func testDiffArgumentsWithoutPathHaveNoPathspec() {
        let args = PRCommands.diffArguments(clone: "/c", n: 7, head: head, path: nil)
        XCTAssertFalse(args.contains("--"))
        XCTAssertEqual(args.last, "refs/glidepath/base/7...abc123")
    }

    func testNameArgumentsUseSameOptions() {
        let args = PRCommands.diffNameArguments(clone: "/c", n: 7, head: head)
        XCTAssertEqual(args, ["-C", "/c", "--literal-pathspecs", "diff", "--name-only", "-z", "--no-renames",
                              "refs/glidepath/base/7...abc123"])
    }

    func testNeedsFetchOnlyWhenHeadOrBaseIsMissing() {
        XCTAssertTrue(PRCommands.needsFetch(nil, head: head, baseFetched: true))
        XCTAssertTrue(PRCommands.needsFetch("old999", head: head, baseFetched: true))
        XCTAssertTrue(PRCommands.needsFetch(head, head: head, baseFetched: false))
        XCTAssertFalse(PRCommands.needsFetch(head, head: head, baseFetched: true))
    }

    func testGitNexusLogKeepsWarningsAndTail() {
        var lines = [#"{"level":30,"msg":"routine"}"#, #"{"level":40,"msg":"warn one"}"#, #"{"level":50,"msg":"error"}"#]
        lines += (1...12).map { "plain \($0)" }
        lines.append(#"{"level":60,"msg":"fatal"}"#)
        let kept = Runner.gitNexusLogLines(lines.joined(separator: "\n"))
        XCTAssertEqual(kept.count, 3 + 8)
        XCTAssertTrue(kept.contains(#"{"level":40,"msg":"warn one"}"#))
        XCTAssertTrue(kept.contains(#"{"level":50,"msg":"error"}"#))
        XCTAssertTrue(kept.contains(#"{"level":60,"msg":"fatal"}"#))
        XCTAssertFalse(kept.contains(#"{"level":30,"msg":"routine"}"#))
        XCTAssertFalse(kept.contains("plain 4"))
        XCTAssertEqual(kept.first, #"{"level":40,"msg":"warn one"}"#, "original order is kept")
    }

    func testGitNexusLogCapsWarnings() {
        let lines = (1...30).map { #"{"level":50,"msg":"e\#($0)"}"# }
        let kept = Runner.gitNexusLogLines(lines.joined(separator: "\n"))
        XCTAssertEqual(kept.count, 20)
        XCTAssertEqual(kept.last, #"{"level":50,"msg":"e30"}"#)
    }

    func testGitNexusLogEmptyOutput() {
        XCTAssertEqual(Runner.gitNexusLogLines("\n  \n"), [])
    }
}
