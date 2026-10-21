import Foundation

/// Every path review-radar reads or writes. `home` comes from $HOME so tests can point it at a temp dir.
struct Paths {
    let home: String

    /// XDG_CONFIG_HOME and XDG_STATE_HOME move review-radar's own folders (for tests and side-by-side
    /// installs). HOME stays as it is: claude and gh find their sign-in through it.
    let configBase: String
    let stateBase: String

    init(home: String? = nil, env: [String: String] = ProcessInfo.processInfo.environment) {
        let h = home ?? env["HOME"] ?? NSHomeDirectory()
        self.home = h
        self.configBase = Paths.absoluteEnv(env["XDG_CONFIG_HOME"]) ?? h + "/.config"
        self.stateBase = Paths.absoluteEnv(env["XDG_STATE_HOME"]) ?? h + "/.local/state"
    }

    /// An XDG value counts only when it is an absolute path; the XDG spec says to ignore anything else.
    static func absoluteEnv(_ value: String?) -> String? {
        guard let v = value, v.hasPrefix("/") else { return nil }
        return v
    }

    var configDir: String { configBase + "/review-radar" }
    var configFile: String { configDir + "/config.toml" }
    var stateDir: String { stateBase + "/review-radar" }
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
