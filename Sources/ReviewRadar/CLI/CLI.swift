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
    review-radar: scheduled Claude Code PR reviews with a menu bar radar.

    Usage:
      review-radar init                      set up config, skill, schedule, app; ends with a dry run
      review-radar run [--dry-run] [--repo owner/name]
                                             run the review pipeline now
      review-radar state set --run ID --repo owner/name --pr N [--stage gather|review|check|post]
                             [--author LOGIN] [--title TEXT] [--verdict approve|changes|skipped] [--reason TEXT]
      review-radar state show [--run ID]     print a run as JSON (default: current)
      review-radar pause | resume            skip or allow scheduled runs
      review-radar doctor                    check requirements and installed pieces
      review-radar uninstall [--purge]       remove the job, skill and app link; --purge also removes config and state
      review-radar                           open the menu bar app (also: review-radar app)
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
        case "pr": return PRCommands.main(rest)
        case "post": return PRCommands.post(rest)
        case "pause": return setPaused(true)
        case "resume": return setPaused(false)
        case "doctor": return Doctor.main()
        case "uninstall": return Uninstall.main(rest)
        case "--version", "version":
            print("review-radar 1.0.0")
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

/// `review-radar state set|show`. The review skill calls `set` at each stage; it never edits JSON.
enum StateCommand {
    static func main(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            eprint("usage: review-radar state set|show ...")
            return 2
        }
        let a = Args(Array(args.dropFirst()), valued: [
            "--run", "--repo", "--pr", "--stage", "--author", "--title", "--verdict", "--reason",
        ])
        let store = RunStore(paths: Paths())
        do {
            switch sub {
            case "set":
                guard let runId = a.value("--run"), let slug = a.value("--repo"),
                      let n = a.value("--pr").flatMap(Int.init) else {
                    eprint("state set needs --run, --repo and a numeric --pr")
                    return 2
                }
                let stage = try a.value("--stage").map { text -> Stage in
                    guard let s = Stage(rawValue: text) else { throw StateError("unknown stage \(text)") }
                    return s
                }
                let verdict = try a.value("--verdict").map { text -> Verdict in
                    guard let v = Verdict(rawValue: text) else { throw StateError("unknown verdict \(text)") }
                    return v
                }
                // Bound to the run in the environment. Stamps belong to `review-radar post`, never here.
                let binding = try RunBinding.current()
                guard runId == binding.runId, slug == binding.repo else {
                    throw StateError("state set is limited to the run and repo in this session")
                }
                guard verdict == nil, stage != .post else {
                    throw StateError("verdicts and the post stage are set by review-radar post")
                }
                try store.mutate(runId) { run in
                    guard run.repos.first(where: { $0.slug == slug })?.prs.contains(where: { $0.n == n }) == true else {
                        throw StateError("unknown PR for this run: \(slug) #\(n)")
                    }
                    try run.setPR(repo: slug, n: n, stage: stage, author: a.value("--author"),
                                  title: a.value("--title"), verdict: nil, reason: nil)
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
                eprint("usage: review-radar state set|show ...")
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
        ]
    }

    static func installed(_ paths: Paths) -> [Item] {
        let fm = FileManager.default
        let uid = getuid()
        return [
            Item(name: "config", ok: (try? Config.load(paths)) != nil, fix: "review-radar init"),
            Item(name: "skill", ok: fm.fileExists(atPath: paths.skillDir + "/SKILL.md"), fix: "review-radar init"),
            Item(name: "scheduled job file", ok: fm.fileExists(atPath: paths.plistFile), fix: "review-radar init"),
            Item(name: "scheduled job loaded",
                 ok: Shell.run("launchctl", ["print", "gui/\(uid)/\(Launchd.label)"]).ok,
                 fix: "launchctl bootstrap gui/\(uid) \(paths.plistFile)"),
            Item(name: "menu bar app link", ok: fm.fileExists(atPath: paths.appLink), fix: "review-radar init"),
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
        print(Pause.isPaused(paths) ? "note  scheduled runs are paused (review-radar resume)" : "ok    scheduled runs are active")
        return items.allSatisfy(\.ok) ? 0 : 1
    }
}

enum Uninstall {
    static func main(_ args: [String]) -> Int32 {
        let purge = Args(args, valued: []).has("--purge")
        let paths = Paths()
        let uid = getuid()

        _ = Shell.run("launchctl", ["bootout", "gui/\(uid)/\(Launchd.label)"])
        remove(paths.plistFile, "scheduled job")
        remove(paths.skillDir, "skill")
        remove(paths.appLink, "app link")
        if purge {
            remove(paths.home + "/.config/review-radar", "config")
            remove(paths.stateDir, "state")
        } else {
            print("kept config and state (use --purge to remove them)")
        }
        print("clones were not touched; delete them by hand if you no longer need them")
        print("the binary and app come from Homebrew: brew uninstall review-radar")
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
