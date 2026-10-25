import Foundation

/// Everything about how a review session is launched. Kept pure so tests can pin the rules.
enum Claude {
    /// The flags below were checked against this version. `doctor` and `init` refuse older ones.
    static let minimumVersion = "2.1.306"

    /// The three review roles. Names are what the skill's Agent calls use, and what `Agent(name)` allows.
    static let agentNames = ["gatherer", "reviewer", "checker"]

    /// GitNexus tools a review may call. Read-only, and scoped to the repo being reviewed.
    /// Excluded on purpose: rename, group_sync, cypher and list_repos (they can write or read other repos).
    static let gitnexusTools = [
        "detect_changes", "impact", "api_impact", "context", "query", "route_map", "shape_check",
    ]

    /// The GitNexus tools as MCP names, for the allowlist and for subagents.
    static var gitnexusMCPTools: [String] { gitnexusTools.map { "mcp__gitnexus__\($0)" } }

    /// Built-in tools a review session may not use, whatever the allowlist says.
    static let disallowed = [
        "WebFetch", "WebSearch", "Skill",
        "Bash(ps:*)", "Bash(du:*)", "Bash(lsof:*)", "Bash(which:*)",
    ]

    /// GitNexus is on when explicitly on, or when auto and the binary exists and the authors are not
    /// "anyone". Anyone-authored PRs are a public input, and GitNexus can read other indexed repos.
    static func gitnexusEnabled(mode: GitNexusMode, authors: AuthorPolicy, binaryFound: Bool) -> Bool {
        switch mode {
        case .on: return true
        case .off: return false
        case .auto:
            if case .anyone = authors { return false }
            return binaryFound
        }
    }

    /// The complete allowlist. No git, no gh, no bare Read, Grep or Glob. Reads are scoped to the
    /// clone and the run scratch directory. Writes are scoped to scratch. Subagents are the three
    /// named roles only, and glidepath's own subcommands are the only shell commands.
    static func allowlist(clone: String, scratch: String, rules: String?, gitnexus: Bool) -> [String] {
        var list = [
            "Read(\(permissionPath(clone))/**)",
            "Read(\(permissionPath(scratch))/**)",
            "Edit(\(permissionPath(scratch))/**)",
        ]
        list += agentNames.map { "Agent(\($0))" }
        list += [
            "Bash(glidepath pr info:*)",
            "Bash(glidepath pr diff:*)",
            "Bash(glidepath pr threads:*)",
            "Bash(glidepath state set:*)",
            "Bash(glidepath post:*)",
            "Bash(glidepath code grep:*)",
            "Bash(glidepath code files:*)",
        ]
        if let rules { list.append("Read(\(permissionPath(rules)))") }
        if gitnexus { list += gitnexusMCPTools }
        return list
    }

    /// Permission rules write absolute paths with a `//` prefix. Our paths already start with "/".
    static func permissionPath(_ absolute: String) -> String {
        "/" + absolute
    }

    /// PATH with `dir` first, so `glidepath` resolves to the binary that started the run.
    /// Without this, a session can fail with "glidepath not on PATH" when the binary is not installed.
    static func pathPrepending(_ dir: String, to path: String?) -> String {
        let parts = (path ?? "").split(separator: ":").map(String.init)
        return ([dir] + parts.filter { $0 != dir }).joined(separator: ":")
    }

    /// Environment for the claude process. Only these pass through; GH_TOKEN and GITHUB_TOKEN never do.
    /// The review wrappers call gh with the user's own sign-in. GH_CONFIG_DIR is pinned by the runner to
    /// the real gh config folder, so gh in the session finds that sign-in even when XDG folders move.
    static func childEnvironment(parent: [String: String], binding: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        for key in ["PATH", "HOME", "USER", "LANG", "TMPDIR", "GH_CONFIG_DIR"] {
            if let v = parent[key] { env[key] = v }
        }
        for (key, value) in parent where key == "ANTHROPIC_API_KEY" || key.hasPrefix("CLAUDE_CODE_") {
            env[key] = value
        }
        for (key, value) in binding { env[key] = value }
        return env
    }

    /// MCP config. Holds only GitNexus when enabled; otherwise no servers at all.
    static func mcpConfig(gitnexus: Bool) -> String {
        let servers: [String: Any] = gitnexus
            ? ["gitnexus": ["command": "gitnexus", "args": ["mcp"]]]
            : [:]
        return json(["mcpServers": servers])
    }

    /// The three review subagents. Each one runs under the session's allowlist and hooks, and in dontAsk.
    /// `tools` names tool families; the command-level limits are the allowlist and the bash guard.
    /// The gatherer also lists the GitNexus MCP tools when GitNexus is on, since a subagent sees only what `tools` names.
    static func agentsJSON(gitnexus: Bool) -> String {
        let common: [String: Any] = [
            "tools": ["Read", "Edit", "Write", "Bash"],
            "permissionMode": "dontAsk",
        ]
        func agent(_ description: String, _ prompt: String, _ model: String) -> [String: Any] {
            common.merging([
                "description": description,
                "prompt": prompt,
                "model": model,
            ]) { $1 }
        }
        var gatherer = agent("Gathers one PR's data into its scratch folder with glidepath pr commands.",
                             "Gather PR data only with glidepath pr info, pr diff, pr threads, code grep, code files and the GitNexus read tools. code files takes no flags. Never run --help or any other shell command. Write only inside the scratch folder you are given. Report gaps.", "haiku")
        if gitnexus {
            gatherer["tools"] = (common["tools"] as? [String] ?? []) + gitnexusMCPTools
        }
        return json([
            "gatherer": gatherer,
            "reviewer": agent("Reviews one PR against the rubric and writes draft.json.",
                              "Review one PR against the rubric. Quote exact lines. Never run --help or any shell command other than glidepath's listed subcommands. Write draft.json only inside the scratch folder you are given.", "sonnet"),
            "checker": agent("Verifies every finding in a draft against the code and writes final.json.",
                             "Re-open every quoted line. Drop findings that do not match. Keep verified blockers. Never run --help or any shell command other than glidepath's listed subcommands. Write final.json only inside the scratch folder you are given.", "sonnet"),
        ])
    }

    /// Settings passed with --settings: one PreToolUse hook on Bash that runs the guard. The command is
    /// exec form (no shell), so the path is not interpreted.
    static func hookSettingsJSON(binary: String) -> String {
        json([
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [[
                        "type": "command",
                        "command": binary,
                        "args": ["hook", "bash-guard"],
                    ]],
                ]],
            ],
        ])
    }

    /// Full argument list for the review session. The skill text is the system prompt; the run
    /// arguments are the user prompt. Nothing is passed as a slash command. `model` is a `ReviewModel` raw value.
    static func arguments(prompt: String, systemPrompt: String, sessionId: String, scratch: String,
                          mcpConfig: String, agents: String, settings: String, allowlist: [String],
                          model: String) -> [String] {
        [
            "-p", prompt,
            "--append-system-prompt", systemPrompt,
            "--model", model,
            "--permission-mode", "dontAsk",
            "--session-id", sessionId,
            // Project and local settings live in the clone, which is untrusted. User settings are the
            // narrowest source claude accepts: user, project, local.
            "--setting-sources", "user",
            "--settings", settings,
            "--strict-mcp-config",
            "--mcp-config", mcpConfig,
            "--agents", agents,
            "--disallowedTools", disallowed.joined(separator: ","),
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

    /// Hook events that would run inside review sessions and can change or observe tool calls.
    static let blockedHookEvents = ["PreToolUse", "PostToolUse", "PermissionRequest"]

    /// Settings-file warnings: broad global allow rules, and hooks of any kind.
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

    /// Blocking hook events found in a settings object. Returns the event names that would run in a review.
    static func blockedHooks(in root: [String: Any]) -> [String] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return blockedHookEvents.filter { event in
            guard let entries = hooks[event] as? [Any] else { return false }
            return !entries.isEmpty
        }
    }

    /// Settings and plugin files that define a blocking hook. Each entry names the file and the events.
    /// Checks the user and local settings, and the hooks.json of plugins that the user's settings enable.
    /// A plugin counts when one of its path components is the enabled plugin's name. If the settings do not
    /// list enabledPlugins at all, every plugin hooks.json counts (fails closed).
    static func hookConflicts(paths: Paths) -> [(file: String, events: [String])] {
        var out: [(String, [String])] = []
        let fm = FileManager.default
        var enabledNames: Set<String>? = nil
        for file in [paths.home + "/.claude/settings.json", paths.home + "/.claude/settings.local.json"] {
            guard let data = fm.contents(atPath: file),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let events = blockedHooks(in: root)
            if !events.isEmpty { out.append((file, events)) }
            if file.hasSuffix("settings.json"), let plugins = root["enabledPlugins"] as? [String: Any] {
                enabledNames = Set(plugins.compactMap { key, value in
                    (value as? Bool) == true ? String(key.split(separator: "@").first ?? "") : nil
                })
            }
        }
        let pluginRoot = paths.home + "/.claude/plugins"
        func enabled(_ rel: String) -> Bool {
            guard let names = enabledNames else { return true }
            return !names.isDisjoint(with: Set(rel.split(separator: "/").map(String.init)))
        }
        if let walker = fm.enumerator(atPath: pluginRoot) {
            for case let rel as String in walker where enabled(rel) {
                let file = pluginRoot + "/" + rel
                // Exact file name: qoder-hooks.json and similar names are not the Claude plugin hooks file.
                if rel == "hooks.json" || rel.hasSuffix("/hooks.json") {
                    if let root = readObject(file) {
                        let events = blockedHooks(in: root)
                        if !events.isEmpty { out.append((file, events)) }
                    }
                }
                // A plugin manifest may point its hooks at another file, or declare them inline.
                if rel == ".claude-plugin/plugin.json" || rel.hasSuffix("/.claude-plugin/plugin.json"),
                   let manifest = readObject(file) {
                    let pluginDir = (file as NSString).deletingLastPathComponent
                        .replacingOccurrences(of: "/.claude-plugin", with: "")
                    if let hooksPath = manifest["hooks"] as? String {
                        let target = pluginDir + "/" + (hooksPath.hasPrefix("./") ? String(hooksPath.dropFirst(2)) : hooksPath)
                        if let root = readObject(target) {
                            let events = blockedHooks(in: root)
                            if !events.isEmpty { out.append((target, events)) }
                        }
                    } else if let inline = manifest["hooks"] as? [String: Any] {
                        let events = blockedHooks(in: ["hooks": inline])
                        if !events.isEmpty { out.append((file, events)) }
                    }
                }
            }
        }
        return out
    }

    private static func readObject(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
