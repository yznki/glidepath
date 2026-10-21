import XCTest
@testable import ReviewRadar

final class SecurityTests: XCTestCase {
    let clone = "/fake/home/clones/api"
    let scratch = "/fake/home/.local/state/review-radar/scratch/r1/acme-api"

    func list(rules: String? = nil, gitnexus: Bool = false) -> [String] {
        Claude.allowlist(clone: clone, scratch: scratch, rules: rules, gitnexus: gitnexus)
    }

    func testAllowlistHasNoGitGhOrBareTools() {
        for entry in list(rules: "/fake/home/rules.md", gitnexus: true) {
            XCTAssertFalse(entry.hasPrefix("Bash(git"), entry)
            XCTAssertFalse(entry.hasPrefix("Bash(gh"), entry)
            XCTAssertFalse(["Read", "Grep", "Glob", "Edit", "Write", "Agent", "Skill"].contains(entry), "bare \(entry)")
        }
    }

    func testReadsAreScopedToCloneAndScratchOnly() {
        let all = list()
        XCTAssertTrue(all.contains("Read(//fake/home/clones/api/**)"))
        XCTAssertTrue(all.contains("Read(//fake/home/.local/state/review-radar/scratch/r1/acme-api/**)"))
        XCTAssertFalse(all.contains { $0.contains(".claude/skills") }, "the skill arrives as system prompt, not a file read")
        XCTAssertEqual(all.filter { $0.hasPrefix("Read(") }.count, 2)
    }

    func testWritesOnlyUnderScratch() {
        XCTAssertEqual(list().filter { $0.hasPrefix("Edit(") },
                       ["Edit(//fake/home/.local/state/review-radar/scratch/r1/acme-api/**)"])
    }

    func testSubagentsAreNamedRolesNotBareAgent() {
        let all = list()
        XCTAssertEqual(Set(all.filter { $0.hasPrefix("Agent") }),
                       ["Agent(gatherer)", "Agent(reviewer)", "Agent(checker)"])
    }

    func testShellIsOnlyReviewRadarSubcommands() {
        XCTAssertEqual(Set(list().filter { $0.hasPrefix("Bash(") }), [
            "Bash(review-radar pr info:*)", "Bash(review-radar pr diff:*)", "Bash(review-radar pr threads:*)",
            "Bash(review-radar state set:*)", "Bash(review-radar post:*)",
        ])
    }

    func testGitNexusListIsReadOnlyAndExact() {
        let mcp = list(gitnexus: true).filter { $0.hasPrefix("mcp__") }
        XCTAssertEqual(Set(mcp), Set(["detect_changes", "impact", "api_impact", "context", "query", "route_map", "shape_check"]
            .map { "mcp__gitnexus__\($0)" }))
        for banned in ["rename", "group_sync", "cypher", "list_repos"] {
            XCTAssertFalse(mcp.contains { $0.hasSuffix(banned) }, banned)
        }
        XCTAssertFalse(list().contains { $0.hasPrefix("mcp__") })
    }

    func testGitNexusAutoIsOffForAnyoneAuthors() {
        XCTAssertFalse(Claude.gitnexusEnabled(mode: .auto, authors: .anyone, binaryFound: true))
        XCTAssertTrue(Claude.gitnexusEnabled(mode: .auto, authors: .collaborators, binaryFound: true))
        XCTAssertTrue(Claude.gitnexusEnabled(mode: .auto, authors: .logins(["a"]), binaryFound: true))
        XCTAssertFalse(Claude.gitnexusEnabled(mode: .auto, authors: .collaborators, binaryFound: false))
        XCTAssertFalse(Claude.gitnexusEnabled(mode: .off, authors: .collaborators, binaryFound: true))
        XCTAssertTrue(Claude.gitnexusEnabled(mode: .on, authors: .anyone, binaryFound: false))
    }

    func testDisallowedCoversWebSkillsAndProcessTools() {
        for tool in ["WebFetch", "WebSearch", "Skill", "Bash(ps:*)", "Bash(du:*)", "Bash(lsof:*)", "Bash(which:*)"] {
            XCTAssertTrue(Claude.disallowed.contains(tool), tool)
        }
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
    }

    func testMCPConfigHoldsOnlyGitNexus() throws {
        let off = try JSONSerialization.jsonObject(with: Data(Claude.mcpConfig(gitnexus: false).utf8)) as? [String: Any]
        XCTAssertEqual((off?["mcpServers"] as? [String: Any])?.count, 0)
        let on = try JSONSerialization.jsonObject(with: Data(Claude.mcpConfig(gitnexus: true).utf8)) as? [String: Any]
        let names = (on?["mcpServers"] as? [String: Any])?.keys.map { $0 } ?? []
        XCTAssertEqual(Set(names), ["gitnexus"])
    }

    func testAgentsDefineThreeRolesWithModels() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(Claude.agentsJSON().utf8)) as? [String: Any]
        XCTAssertEqual(Set(obj?.keys.map { $0 } ?? []), ["gatherer", "reviewer", "checker"])
        XCTAssertEqual((obj?["gatherer"] as? [String: Any])?["model"] as? String, "haiku")
        XCTAssertEqual((obj?["reviewer"] as? [String: Any])?["model"] as? String, "sonnet")
        XCTAssertEqual((obj?["checker"] as? [String: Any])?["permissionMode"] as? String, "dontAsk")
    }

    func testArgumentsCarrySkillAsSystemPromptAndNoSlashCommand() {
        let args = Claude.arguments(prompt: "Review run. repo=a/b", systemPrompt: "SKILL TEXT", sessionId: "s",
                                    scratch: scratch, mcpConfig: "/m.json", agents: "{}", settings: "{}",
                                    allowlist: list())
        XCTAssertEqual(args[args.firstIndex(of: "-p")! + 1], "Review run. repo=a/b")
        XCTAssertFalse(args[args.firstIndex(of: "-p")! + 1].hasPrefix("/"))
        XCTAssertEqual(args[args.firstIndex(of: "--append-system-prompt")! + 1], "SKILL TEXT")
        XCTAssertEqual(args[args.firstIndex(of: "--setting-sources")! + 1], "user")
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertEqual(args[args.firstIndex(of: "--disallowedTools")! + 1], Claude.disallowed.joined(separator: ","))
        XCTAssertEqual(args[args.firstIndex(of: "--permission-mode")! + 1], "dontAsk")
        XCTAssertFalse(args.joined(separator: " ").contains("bypassPermissions"))
    }

    func testVersionComparison() {
        XCTAssertTrue(Claude.isVersion("2.1.306 (Claude Code)", atLeast: "2.1.306"))
        XCTAssertTrue(Claude.isVersion("2.2.0", atLeast: "2.1.306"))
        XCTAssertFalse(Claude.isVersion("2.1.305 (Claude Code)", atLeast: "2.1.306"))
    }

    func testSettingsWarnings() {
        let broad: [String: Any] = [
            "permissions": ["allow": ["Bash(*)", "Bash(npm test)", "Read"]],
            "hooks": ["PreToolUse": [] as [Any]],
        ]
        XCTAssertEqual(Claude.settingsWarnings(broad).count, 3)
        XCTAssertTrue(Claude.settingsWarnings(["permissions": ["allow": ["Bash(npm test)"]]]).isEmpty)
    }

    func testBlockedHookEvents() {
        XCTAssertEqual(Claude.blockedHooks(in: ["hooks": ["PreToolUse": [["matcher": "Bash"]]]]), ["PreToolUse"])
        XCTAssertEqual(Claude.blockedHooks(in: ["hooks": ["PostToolUse": [1], "PermissionRequest": [2]]]),
                       ["PostToolUse", "PermissionRequest"])
        XCTAssertEqual(Claude.blockedHooks(in: ["hooks": ["SessionStart": [1], "UserPromptSubmit": [1], "Stop": [1]]]), [])
        XCTAssertEqual(Claude.blockedHooks(in: ["hooks": ["PreToolUse": []]]), [], "an empty list defines nothing")
    }

    func testHookConflictsScanSettingsAndPlugins() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rr-hooks-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try FileManager.default.createDirectory(atPath: home + "/.claude/plugins/cache/p", withIntermediateDirectories: true)
        try Data(#"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[]}]}}"#.utf8)
            .write(to: URL(fileURLWithPath: home + "/.claude/settings.json"))
        try Data(#"{"hooks":{"SessionStart":[]}}"#.utf8)
            .write(to: URL(fileURLWithPath: home + "/.claude/settings.local.json"))
        try Data(#"{"hooks":{"PostToolUse":[{"matcher":"*"}]}}"#.utf8)
            .write(to: URL(fileURLWithPath: home + "/.claude/plugins/cache/p/hooks.json"))
        try FileManager.default.createDirectory(atPath: home + "/.claude/plugins/cache/off", withIntermediateDirectories: true)
        try Data(#"{"hooks":{"PreToolUse":[{"matcher":"*"}]}}"#.utf8)
            .write(to: URL(fileURLWithPath: home + "/.claude/plugins/cache/off/hooks.json"))
        // A manifest that points at another file, and an inline manifest hook, both count for enabled plugins.
        try FileManager.default.createDirectory(atPath: home + "/.claude/plugins/cache/p/.claude-plugin", withIntermediateDirectories: true)
        try Data(#"{"hooks":"./hooks/other.json"}"#.utf8).write(to: URL(fileURLWithPath: home + "/.claude/plugins/cache/p/.claude-plugin/plugin.json"))
        try FileManager.default.createDirectory(atPath: home + "/.claude/plugins/cache/p/hooks", withIntermediateDirectories: true)
        try Data(#"{"hooks":{"PreToolUse":[{"matcher":"*"}]}}"#.utf8).write(to: URL(fileURLWithPath: home + "/.claude/plugins/cache/p/hooks/other.json"))
        // Only "p" is enabled, so the hooks of plugin "off" do not count.
        try Data(#"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[]}]},"enabledPlugins":{"p@market":true,"off@market":false}}"#.utf8)
            .write(to: URL(fileURLWithPath: home + "/.claude/settings.json"))
        let found = Claude.hookConflicts(paths: Paths(home: home))
        XCTAssertEqual(found.count, 3)
        XCTAssertTrue(found.contains { $0.file.hasSuffix("p/hooks/other.json") })
        XCTAssertFalse(found.contains { $0.file.contains("/off/") })
        XCTAssertTrue(found.contains { $0.file.hasSuffix("settings.json") && $0.events == ["PreToolUse"] })
        XCTAssertTrue(found.contains { $0.file.hasSuffix("hooks.json") && $0.events == ["PostToolUse"] })
    }

    func testStateSetFlagsAreStrict() throws {
        let ok = try StrictFlags.parse(["--run", "r", "--repo", "a/b", "--pr", "3", "--stage", "review"],
                                       allowed: ["--run", "--repo", "--pr", "--stage", "--reason"])
        XCTAssertEqual(ok["--pr"], "3")
        XCTAssertThrowsError(try StrictFlags.parse(["--author", "x"], allowed: ["--run"]))
        XCTAssertThrowsError(try StrictFlags.parse(["--run=r"], allowed: ["--run"]))
        XCTAssertThrowsError(try StrictFlags.parse(["--run", "a", "--run", "b"], allowed: ["--run"]))
        XCTAssertThrowsError(try StrictFlags.parse(["stray"], allowed: ["--run"]))
    }

    func testReasonLimits() {
        XCTAssertNil(try? StrictFlags.reason([:]))
        XCTAssertEqual(try StrictFlags.reason(["--reason": "ok"]), "ok")
        XCTAssertThrowsError(try StrictFlags.reason(["--reason": String(repeating: "x", count: 201)]))
        XCTAssertThrowsError(try StrictFlags.reason(["--reason": "a\nb"]))
    }

    func testChildPathStartsWithRunningBinaryDirectory() {
        XCTAssertEqual(Claude.pathPrepending("/opt/rr/bin", to: "/usr/bin:/bin"), "/opt/rr/bin:/usr/bin:/bin")
        XCTAssertEqual(Claude.pathPrepending("/opt/rr/bin", to: "/usr/bin:/opt/rr/bin"), "/opt/rr/bin:/usr/bin")
        XCTAssertEqual(Claude.pathPrepending("/opt/rr/bin", to: nil), "/opt/rr/bin")
    }
}
