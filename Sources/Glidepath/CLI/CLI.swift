import Foundation

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Minimal flag parser: `valued` flags take the next argument, everything else is a switch.
struct Args {
    private(set) var values: [String: String] = [:]
    private(set) var switches: Set<String> = []

    init(_ raw: [String], valued: Set<String>) {
        var i = 0
        while i < raw.count {
            if valued.contains(raw[i]), i + 1 < raw.count {
                values[raw[i]] = raw[i + 1]
                i += 2
            } else {
                switches.insert(raw[i])
                i += 1
            }
        }
    }

    func has(_ flag: String) -> Bool { switches.contains(flag) }
    func value(_ flag: String) -> String? { values[flag] }
}

enum CLI {
    static let usage = """
    glidepath: scheduled Claude Code PR reviews with a menu bar radar.

    Usage:
      glidepath init                      set up config, skill, schedule, app; ends with a dry run
      glidepath run [--dry-run] [--repo owner/name]
                                             run the review pipeline now
      glidepath state set --run ID --repo owner/name --pr N [--stage gather|review|check] [--reason TEXT]
      glidepath state show [--run ID]     print a run as JSON (default: current)
      glidepath pause | resume            skip or allow scheduled runs
      glidepath doctor                    check requirements and installed pieces
      glidepath uninstall [--purge]       remove the job, skill and app link; --purge also removes config and state
      glidepath                           open the menu bar app (also: glidepath app)
    """

    static func main(_ argv: [String]) -> Int32 {
        let rest = Array(argv.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            print(usage)
            return 0
        }
        switch argv.first {
        case "run": return RunCommand.main(rest)
        case "init": return InitCommand.main(rest)
        case "state": return StateCommand.main(rest)
        case "hook": return HookCommand.main(rest)
        case "code": return CodeCommands.main(rest)
        case "pr": return PRCommands.main(rest)
        case "post": return PRCommands.post(rest)
        case "pause": return setPaused(true)
        case "resume": return setPaused(false)
        case "doctor": return Doctor.main()
        case "uninstall": return Uninstall.main(rest)
        case "--version", "version":
            print("glidepath 1.0.2")
            return 0
        case "-h", "--help", "help":
            print(usage)
            return 0
        default:
            eprint("unknown command \(argv[0])\n\n" + usage)
            return 2
        }
    }

    private static func setPaused(_ on: Bool) -> Int32 {
        do {
            try Pause.set(on, Paths())
            print(on ? "paused: scheduled runs are skipped until resume" : "resumed: scheduled runs will run")
            return 0
        } catch {
            eprint("\(error)")
            return 1
        }
    }
}

/// `glidepath state set|show`. The review skill calls `set` at each stage; it never edits JSON.
enum StateCommand {
    static func main(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            eprint("usage: glidepath state set|show ...")
            return 2
        }
        let a = Args(Array(args.dropFirst()), valued: [
            "--run", "--repo", "--pr", "--stage", "--author", "--title", "--verdict", "--reason",
        ])
        let store = RunStore(paths: Paths())
        do {
            switch sub {
            case "set":
                let f = try StrictFlags.parse(Array(args.dropFirst()), allowed: ["--run", "--repo", "--pr", "--stage", "--reason"])
                guard let runId = f["--run"] else { throw StateError("state set needs --run") }
                let slug = try StrictFlags.repo(f)
                let n = try StrictFlags.pr(f)
                let stage = try f["--stage"].map { text -> Stage in
                    guard let s = Stage(rawValue: text), s != .post else {
                        throw StateError("stage must be gather, review or check; post is set by glidepath post")
                    }
                    return s
                }
                let note = try StrictFlags.reason(f)
                // Bound to the run and repo in the environment. Stamps belong to `glidepath post`.
                let binding = try RunBinding.current()
                guard runId == binding.runId, slug == binding.repo else {
                    throw StateError("state set is limited to the run and repo in this session")
                }
                try store.mutate(runId) { run in
                    guard run.repos.first(where: { $0.slug == slug })?.prs.contains(where: { $0.n == n }) == true else {
                        throw StateError("unknown PR for this run: \(slug) #\(n)")
                    }
                    try run.setPR(repo: slug, n: n, stage: stage, author: nil, title: nil, verdict: nil, reason: nil)
                    if let note { try run.setNote(repo: slug, n: n, note: note) }
                }
                print("ok")
                return 0
            case "show":
                let run: RunState?
                if let id = a.value("--run") {
                    run = try store.load(id)
                } else {
                    run = try store.loadCurrent()
                }
                guard let run else {
                    eprint("no current run")
                    return 1
                }
                let data = try RunStore.encoder().encode(run)
                print(String(decoding: data, as: UTF8.self))
                return 0
            default:
                eprint("usage: glidepath state set|show ...")
                return 2
            }
        } catch {
            eprint("\(error)")
            return 1
        }
    }
}

/// Requirement checks shared by `init` (which stops on a failed required check) and `doctor`.
enum Checks {
    struct Item {
        let name: String
        let ok: Bool
        let fix: String
    }

    static func tools() -> [Item] {
        [
            Item(name: "Xcode Command Line Tools", ok: Shell.run("xcode-select", ["-p"]).ok,
                 fix: "xcode-select --install"),
            Item(name: "git", ok: Shell.find("git") != nil, fix: "xcode-select --install"),
            Item(name: "gh (GitHub CLI)", ok: Shell.find("gh") != nil, fix: "brew install gh"),
            Item(name: "gh signed in", ok: Shell.run("gh", ["auth", "status"]).ok, fix: "gh auth login"),
            Item(name: "claude (Claude Code)", ok: Shell.find("claude") != nil,
                 fix: "brew install --cask claude-code, then run claude once and log in"),
            claudeVersion(),
            ghRepoScope(),
        ]
    }

    /// The review sessions use flags that exist from `Claude.minimumVersion` on.
    static func claudeVersion() -> Item {
        let r = Shell.run("claude", ["--version"], timeout: 30)
        let reported = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = r.ok && Claude.isVersion(reported, atLeast: Claude.minimumVersion)
        return Item(name: "claude version \(Claude.minimumVersion) or later (found \(reported.isEmpty ? "none" : reported))",
                    ok: ok, fix: "update Claude Code to \(Claude.minimumVersion) or later")
    }

    /// Private repos need the `repo` scope. A token that does not list scopes (fine-grained) is flagged too.
    static func ghRepoScope() -> Item {
        let r = Shell.run("gh", ["auth", "status"], timeout: 30)
        let text = r.stdout + r.stderr
        let line = text.split(separator: "\n").first { $0.contains("Token scopes:") }
        let ok = line.map { $0.contains("'repo'") } ?? false
        return Item(name: "gh token has the repo scope", ok: ok,
                    fix: "gh auth refresh -s repo (a token without listed scopes needs repo access to private repos)")
    }

    /// Global settings still load inside review sessions under `--setting-sources user`.
    static func userSettingsNotes() -> [String] {
        let path = Paths().home + "/.claude/settings.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return Claude.settingsWarnings(root)
    }

    static func installed(_ paths: Paths) -> [Item] {
        let fm = FileManager.default
        let uid = getuid()
        return [
            Item(name: "config", ok: (try? Config.load(paths)) != nil, fix: "glidepath init"),
            Item(name: "skill", ok: fm.fileExists(atPath: paths.skillDir + "/SKILL.md"), fix: "glidepath init"),
            Item(name: "scheduled job file", ok: fm.fileExists(atPath: paths.plistFile), fix: "glidepath init"),
            Item(name: "scheduled job loaded",
                 ok: Shell.run("launchctl", ["print", "gui/\(uid)/\(Launchd.label)"]).ok,
                 fix: "launchctl bootstrap gui/\(uid) \(paths.plistFile)"),
            Item(name: "menu bar app link", ok: fm.fileExists(atPath: paths.appLink), fix: "glidepath init"),
        ]
    }
}

enum Doctor {
    static func main() -> Int32 {
        let paths = Paths()
        let items = Checks.tools() + Checks.installed(paths)
        for item in items {
            print(item.ok ? "ok    \(item.name)" : "FAIL  \(item.name): \(item.fix)")
        }
        print(Pause.isPaused(paths) ? "note  scheduled runs are paused (glidepath resume)" : "ok    scheduled runs are active")
        for note in Checks.userSettingsNotes() {
            print("warn  ~/.claude/settings.json: \(note)")
        }
        // The same check `run` makes: user hooks that would run inside review sessions block the run.
        let conflicts = Claude.hookConflicts(paths: paths)
        for conflict in conflicts {
            print("FAIL  \(conflict.file) defines \(conflict.events.joined(separator: ", ")) hooks; run refuses until they are moved")
        }
        if conflicts.isEmpty { print("ok    no user hooks that would run inside review sessions") }
        return items.allSatisfy(\.ok) && Claude.hookConflicts(paths: paths).isEmpty ? 0 : 1
    }
}

enum Uninstall {
    static func main(_ args: [String]) -> Int32 {
        let a = Args(args, valued: [])
        let paths = Paths()
        let fm = FileManager.default
        let uid = getuid()

        // The login item belongs to the app bundle, so the app unregisters it.
        let appBinary = paths.appLink + "/Contents/MacOS/glidepath"
        if fm.fileExists(atPath: appBinary) {
            let r = Shell.run(appBinary, ["--unregister-login"], timeout: 30)
            if !r.ok { eprint("could not remove the login item; remove it in System Settings > General > Login Items") }
        }

        _ = Shell.run("launchctl", ["bootout", "gui/\(uid)/\(Launchd.label)"])
        remove(paths.plistFile, "scheduled job")
        remove(paths.skillDir, "skill")
        remove(paths.appLink, "app link")

        if a.has("--purge") {
            let configDir = paths.configDir
            let rules = configDir + "/rules"
            var keepRules = false
            if fm.fileExists(atPath: rules) {
                if a.has("--yes") {
                    keepRules = false
                } else {
                    print("Delete your rules files in \(rules)? They are yours to edit; deleting cannot be undone. [y/N] ",
                          terminator: "")
                    keepRules = !(readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "y")
                }
            }
            if keepRules {
                print("kept \(rules)")
                remove(configDir + "/config.toml", "config")
            } else {
                remove(configDir, "config")
            }
            remove(paths.stateDir, "state")
        } else {
            print("kept config and state (use --purge to remove them)")
        }
        print("clones were not touched; delete them by hand if you no longer need them")
        print("the binary and app come from Homebrew: brew uninstall glidepath")
        return 0
    }

    private static func remove(_ path: String, _ label: String) {
        // fileExists follows symlinks, so a dangling app link is checked separately.
        guard FileManager.default.fileExists(atPath: path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
            print("removed \(label): \(path)")
        } catch {
            eprint("could not remove \(label) at \(path): \(error.localizedDescription)")
        }
    }
}

/// `glidepath hook bash-guard`: the PreToolUse hook that review sessions run for every Bash call.
enum HookCommand {
    static func main(_ args: [String]) -> Int32 {
        // First thing: a closed stderr must not kill the guard with SIGPIPE (exit 141) before it denies.
        signal(SIGPIPE, SIG_IGN)
        guard args == ["bash-guard"] else {
            eprint("usage: glidepath hook bash-guard")
            return 2
        }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let decision = BashGuard.evaluate(stdin: input)
        // A raw write: FileHandle.write raises on a closed pipe, and the decision must still be returned.
        if let message = decision.message {
            let bytes = Array((message + "\n").utf8)
            _ = bytes.withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
        }
        return decision.code
    }
}
