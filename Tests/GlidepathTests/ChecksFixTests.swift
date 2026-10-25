import XCTest
@testable import Glidepath

final class ChecksFixTests: XCTestCase {
    private func item(_ name: String, _ command: String?) -> Checks.Item {
        Checks.Item(name: name, ok: false, fix: "fix", command: command)
    }

    private let known: Set<String> = [
        "xcode-select --install", "brew install gh", "gh auth login", "brew install --cask claude-code",
        "claude update", "gh auth refresh -s repo", "glidepath init --refresh",
    ]

    func testNothingRunnableMeansNoScript() {
        XCTAssertNil(Checks.fixScript([]))
        XCTAssertNil(Checks.fixScript([item("config", nil)]))
        XCTAssertNil(Checks.fixAllLine([item("config", nil)]))
    }

    func testCommandsRunInOrderOnce() throws {
        let script = try XCTUnwrap(Checks.fixScript([
            item("CLT", "xcode-select --install"),
            item("gh", "brew install gh"),
            item("git", "xcode-select --install"),
        ]))
        let lines = script.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "#!/bin/zsh")
        XCTAssertEqual(lines[1], #"export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH""#)
        XCTAssertEqual(Array(lines[2...5]), [
            #"echo "→ xcode-select --install""#, "xcode-select --install",
            #"echo "→ brew install gh""#, "brew install gh",
        ])
        XCTAssertEqual(lines[6], #"echo; echo "Done. Back in Glidepath, click Check again.""#)
    }

    func testGhLoginReplacesRefresh() {
        let script = Checks.fixScript([item("scope", "gh auth refresh -s repo"), item("signed in", "gh auth login")]) ?? ""
        XCTAssertFalse(script.contains("gh auth refresh"))
        XCTAssertTrue(script.contains("gh auth login"))
    }

    func testRefreshKeptWithoutLogin() {
        let script = Checks.fixScript([item("scope", "gh auth refresh -s repo")]) ?? ""
        XCTAssertTrue(script.contains("gh auth refresh -s repo"))
    }

    func testClaudeInstallReplacesUpdate() {
        let script = Checks.fixScript([item("version", "claude update"), item("claude", "brew install --cask claude-code")]) ?? ""
        XCTAssertFalse(script.contains("claude update"))
        XCTAssertTrue(script.contains("brew install --cask claude-code"))
    }

    func testScriptHoldsOnlyKnownCommands() {
        let script = Checks.fixScript(known.sorted().map { item($0, $0) }) ?? ""
        for line in script.components(separatedBy: "\n")
        where !line.isEmpty && !line.hasPrefix("#!") && !line.hasPrefix("export ") && !line.hasPrefix("echo") {
            XCTAssertTrue(known.contains(line), line)
        }
    }

    func testFixAllLineJoinsDedupedCommands() {
        XCTAssertEqual(Checks.fixAllLine([
            item("CLT", "xcode-select --install"), item("gh", "brew install gh"), item("git", "xcode-select --install"),
        ]), "Fix all: xcode-select --install && brew install gh")
    }
}
