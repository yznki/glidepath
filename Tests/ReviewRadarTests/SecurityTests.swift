import XCTest
@testable import ReviewRadar

final class SecurityTests: XCTestCase {
    let clone = "/fake/home/clones/api"
    let scratch = "/fake/home/.local/state/review-radar/scratch/r1/acme-api"
    let skill = "/fake/home/.claude/skills/review-radar"

    func list(rules: String? = nil, gitnexus: Bool = false) -> [String] {
        Claude.allowlist(clone: clone, scratch: scratch, skillDir: skill, rules: rules, gitnexus: gitnexus)
    }

    func testAllowlistHasNoGitGhOrBareTools() {
        let all = list(rules: "/fake/home/rules.md", gitnexus: true)
        for entry in all {
            XCTAssertFalse(entry.hasPrefix("Bash(git"), entry)
            XCTAssertFalse(entry.hasPrefix("Bash(gh"), entry)
            XCTAssertFalse(["Read", "Grep", "Glob", "Edit", "Write"].contains(entry), "bare tool \(entry)")
        }
        XCTAssertFalse(all.contains { $0.contains("bypass") })
    }

    func testAllowlistIsScopedAndUsesDoubleSlashAbsolutePaths() {
        let all = list()
        XCTAssertTrue(all.contains("Read(//fake/home/clones/api/**)"))
        XCTAssertTrue(all.contains("Read(//fake/home/.local/state/review-radar/scratch/r1/acme-api/**)"))
        XCTAssertTrue(all.contains("Read(//fake/home/.claude/skills/review-radar/**)"))
        XCTAssertTrue(all.contains("Edit(//fake/home/.local/state/review-radar/scratch/r1/acme-api/**)"))
        XCTAssertFalse(all.contains { $0.hasPrefix("Edit(") && !$0.contains("scratch") }, "writes only under scratch")
    }

    func testAllowlistReviewToolsAreOwnSubcommandsOnly() {
        let bash = list().filter { $0.hasPrefix("Bash(") }
        XCTAssertEqual(Set(bash), [
            "Bash(review-radar pr info:*)", "Bash(review-radar pr diff:*)", "Bash(review-radar pr threads:*)",
            "Bash(review-radar state set:*)", "Bash(review-radar post:*)",
        ])
    }

    func testGitNexusAndRulesAreOptIn() {
        XCTAssertFalse(list().contains { $0.hasPrefix("mcp__") })
        XCTAssertTrue(list(gitnexus: true).contains("mcp__gitnexus__*"))
        XCTAssertTrue(list(rules: "/fake/home/rules.md").contains("Read(//fake/home/rules.md)"))
    }

    func testChildEnvironmentDropsTokens() {
        let parent = [
            "PATH": "/usr/bin", "HOME": "/h", "USER": "u", "LANG": "en_US.UTF-8", "TMPDIR": "/t",
            "GH_TOKEN": "secret1", "GITHUB_TOKEN": "secret2", "SSH_AUTH_SOCK": "/s",
            "ANTHROPIC_API_KEY": "k", "CLAUDE_CODE_OAUTH": "o", "AWS_SECRET_ACCESS_KEY": "x",
        ]
        let env = Claude.childEnvironment(parent: parent, binding: ["REVIEW_RADAR_RUN": "r1"])
        XCTAssertEqual(Set(env.keys), [
            "PATH", "HOME", "USER", "LANG", "TMPDIR", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH", "REVIEW_RADAR_RUN",
        ])
        XCTAssertFalse(env.values.contains("secret1"))
        XCTAssertFalse(env.values.contains("secret2"))
    }

    func testMCPConfigHoldsOnlyGitNexus() throws {
        let off = try JSONSerialization.jsonObject(with: Data(Claude.mcpConfig(gitnexus: false).utf8)) as? [String: Any]
        XCTAssertEqual((off?["mcpServers"] as? [String: Any])?.count, 0)
        let on = try JSONSerialization.jsonObject(with: Data(Claude.mcpConfig(gitnexus: true).utf8)) as? [String: Any]
        let names = (on?["mcpServers"] as? [String: Any])?.keys.map { $0 } ?? []
        XCTAssertEqual(Set(names), ["gitnexus"])
    }

    func testArgumentsNarrowSettingsMCPAndNeverBypass() {
        let args = Claude.arguments(prompt: "p", sessionId: "s", scratch: scratch,
                                    mcpConfig: "{}", allowlist: list())
        XCTAssertEqual(args[args.firstIndex(of: "--setting-sources")! + 1], "user")
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertEqual(args[args.firstIndex(of: "--disallowedTools")! + 1], "WebFetch,WebSearch")
        XCTAssertEqual(args[args.firstIndex(of: "--permission-mode")! + 1], "dontAsk")
        XCTAssertFalse(args.joined(separator: " ").contains("bypassPermissions"))
    }

    func testVersionComparison() {
        XCTAssertTrue(Claude.isVersion("2.1.306 (Claude Code)", atLeast: "2.1.306"))
        XCTAssertTrue(Claude.isVersion("2.2.0", atLeast: "2.1.306"))
        XCTAssertFalse(Claude.isVersion("2.1.305 (Claude Code)", atLeast: "2.1.306"))
        XCTAssertFalse(Claude.isVersion("1.9.9", atLeast: "2.1.306"))
    }

    func testSettingsWarnings() {
        let broad: [String: Any] = [
            "permissions": ["allow": ["Bash(*)", "Bash(npm test)", "Read"]],
            "hooks": ["PreToolUse": [] as [Any]],
        ]
        let w = Claude.settingsWarnings(broad)
        XCTAssertEqual(w.count, 4)
        XCTAssertTrue(Claude.settingsWarnings(["permissions": ["allow": ["Bash(npm test)"]]]).isEmpty)
    }
}

final class ReviewValidatorTests: XCTestCase {
    let files: Set<String> = ["a.swift", "b.swift"]

    func draft(verdict: String = "changes", reason: String = "missing test", body: String = "Looks off.",
               comments: [DraftComment] = []) -> Draft {
        Draft(verdict: verdict, reason: reason, body: body, comments: comments)
    }

    func comment(_ path: String = "a.swift", line: Int = 3, body: String = "fix") -> DraftComment {
        DraftComment(path: path, line: line, side: nil, body: body)
    }

    func testCommentModeBuildsCommentWithVerdictLine() throws {
        let p = try ReviewValidator.validate(draft(comments: [comment()]), files: files, posting: .comment, head: "abc")
        XCTAssertEqual(p.event, "COMMENT")
        XCTAssertEqual(p.commit_id, "abc")
        XCTAssertTrue(p.body.hasPrefix("Verdict: changes\n\n"))
        XCTAssertEqual(p.comments, [PayloadComment(path: "a.swift", line: 3, side: "RIGHT", body: "fix")])
    }

    func testReviewModeMapsVerdictToEvent() throws {
        XCTAssertEqual(try ReviewValidator.validate(draft(verdict: "approve"), files: files, posting: .review, head: "h").event, "APPROVE")
        XCTAssertEqual(try ReviewValidator.validate(draft(), files: files, posting: .review, head: "h").event, "REQUEST_CHANGES")
    }

    func testRefusals() {
        func refused(_ d: Draft, _ why: String, line: UInt = #line) {
            XCTAssertThrowsError(try ReviewValidator.validate(d, files: files, posting: .comment, head: "h"), why, file: #filePath, line: line)
        }
        refused(draft(verdict: "merge"), "bad verdict")
        refused(draft(reason: String(repeating: "x", count: 61)), "reason too long")
        refused(draft(reason: "two\nlines"), "multi-line reason")
        refused(draft(body: String(repeating: "x", count: 6001)), "body too long")
        refused(draft(body: "  "), "empty body")
        refused(draft(comments: Array(repeating: comment(), count: 6)), "six comments")
        refused(draft(comments: [comment("../etc/passwd")]), "path not in PR")
        refused(draft(comments: [comment("c.swift")]), "path not in PR")
        refused(draft(comments: [comment(line: 0)]), "line zero")
        refused(draft(comments: [comment(body: String(repeating: "x", count: 1501))]), "comment too long")
        refused(draft(comments: [DraftComment(path: "a.swift", line: 1, side: "LEFT", body: "x")]), "LEFT side")
    }

    func testFiveCommentsAllowed() {
        XCTAssertNoThrow(try ReviewValidator.validate(draft(comments: Array(repeating: comment(), count: 5)),
                                                      files: files, posting: .comment, head: "h"))
    }
}
