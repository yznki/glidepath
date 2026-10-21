import Foundation

/// Everything about how a review session is launched. Kept pure so tests can pin the rules.
enum Claude {
    /// The flags below were checked against this version. `doctor` and `init` refuse older ones.
    static let minimumVersion = "2.1.306"

    /// The complete allowlist. No git, no gh, no bare Read, Grep or Glob. Reads are scoped to the
    /// clone, the run scratch directory and the installed skill. Writes are scoped to scratch.
    /// The review tools are review-radar's own subcommands, which validate against the run.
    static func allowlist(clone: String, scratch: String, skillDir: String, rules: String?, gitnexus: Bool) -> [String] {
        var list = [
            "Read(\(permissionPath(clone))/**)",
            "Read(\(permissionPath(scratch))/**)",
            "Read(\(permissionPath(skillDir))/**)",
            "Edit(\(permissionPath(scratch))/**)",
            "Agent",
            "Bash(review-radar pr info:*)",
            "Bash(review-radar pr diff:*)",
            "Bash(review-radar pr threads:*)",
            "Bash(review-radar state set:*)",
            "Bash(review-radar post:*)",
        ]
        if let rules { list.append("Read(\(permissionPath(rules)))") }
        if gitnexus { list.append("mcp__gitnexus__*") }
        return list
    }

    /// Permission rules write absolute paths with a `//` prefix. Our paths already start with "/".
    static func permissionPath(_ absolute: String) -> String {
        "/" + absolute
    }

    /// Environment for the claude process. Only these pass through; GH_TOKEN and GITHUB_TOKEN never do.
    /// The review wrappers call gh with the user's own sign-in, which lives in the keychain and gh's config.
    static func childEnvironment(parent: [String: String], binding: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        for key in ["PATH", "HOME", "USER", "LANG", "TMPDIR"] {
            if let v = parent[key] { env[key] = v }
        }
        for (key, value) in parent where key == "ANTHROPIC_API_KEY" || key.hasPrefix("CLAUDE_CODE_") {
            env[key] = value
        }
        for (key, value) in binding { env[key] = value }
        return env
    }

    /// MCP config. Holds only GitNexus when enabled; otherwise no servers at all.
    /// `--strict-mcp-config` makes claude ignore every other MCP configuration.
    static func mcpConfig(gitnexus: Bool) -> String {
        let servers: [String: Any] = gitnexus
            ? ["gitnexus": ["command": "gitnexus", "args": ["mcp"]]]
            : [:]
        let data = (try? JSONSerialization.data(withJSONObject: ["mcpServers": servers],
                                                options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static func arguments(prompt: String, sessionId: String, scratch: String, mcpConfig: String,
                          allowlist: [String]) -> [String] {
        [
            "-p", prompt,
            "--model", "opus",
            "--permission-mode", "dontAsk",
            "--session-id", sessionId,
            // Project and local settings live in the clone, which is untrusted. User settings are the
            // narrowest source claude accepts: user, project, local.
            "--setting-sources", "user",
            "--strict-mcp-config",
            "--mcp-config", mcpConfig,
            "--disallowedTools", "WebFetch,WebSearch",
            "--add-dir", scratch,
            "--allowedTools", allowlist.joined(separator: ","),
        ]
    }

    /// True when `reported` (for example "2.1.306 (Claude Code)") is at least `minimum`.
    static func isVersion(_ reported: String, atLeast minimum: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            let head = s.split(separator: " ").first.map(String.init) ?? s
            return head.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(reported), b = parts(minimum)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }

    /// Warnings about the user's global settings, which still load under `--setting-sources user`.
    static func settingsWarnings(_ root: [String: Any]) -> [String] {
        var out: [String] = []
        let permissions = root["permissions"] as? [String: Any] ?? [:]
        for rule in permissions["allow"] as? [String] ?? [] {
            if ["Bash", "Bash(*)", "Read", "Edit", "Write"].contains(rule) || rule.hasPrefix("Bash(*") || rule.hasPrefix("mcp__*") {
                out.append("global allow rule \"\(rule)\" is broader than review sessions need; it applies to them too")
            }
        }
        if let hooks = root["hooks"] as? [String: Any], !hooks.isEmpty {
            out.append("global hooks run inside review sessions: \(hooks.keys.sorted().joined(separator: ", "))")
        }
        return out
    }
}
