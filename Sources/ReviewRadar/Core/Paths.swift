import Foundation

/// Every path review-radar reads or writes. `home` comes from $HOME so tests can point it at a temp dir.
struct Paths {
    let home: String

    init(home: String? = nil) {
        self.home = home ?? ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    var configFile: String { home + "/.config/review-radar/config.toml" }
    var stateDir: String { home + "/.local/state/review-radar" }
    var runsDir: String { stateDir + "/runs" }
    var currentLink: String { stateDir + "/current" }
    var pausedFile: String { stateDir + "/paused" }
    var lockFile: String { stateDir + "/run.lock" }
    var scratchDir: String { stateDir + "/scratch" }
    var skillDir: String { home + "/.claude/skills/review-radar" }
    var appsDir: String { home + "/Applications" }
    var appLink: String { appsDir + "/Review Radar.app" }
    var agentsDir: String { home + "/Library/LaunchAgents" }
    var plistFile: String { agentsDir + "/\(Launchd.label).plist" }
    var logFile: String { home + "/Library/Logs/review-radar.log" }
    var claudeProjectsDir: String { home + "/.claude/projects" }

    func runFile(_ id: String) -> String { runsDir + "/\(id).json" }

    /// Expands a leading `~/` against `home`.
    func expand(_ path: String) -> String {
        path.hasPrefix("~/") ? home + String(path.dropFirst(1)) : path
    }
}
