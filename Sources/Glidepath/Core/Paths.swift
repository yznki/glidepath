import Foundation

/// Every path glidepath reads or writes. `home` comes from $HOME so tests can point it at a temp dir.
struct Paths {
    let home: String

    /// XDG_CONFIG_HOME and XDG_STATE_HOME move glidepath's own folders (for tests and side-by-side
    /// installs). HOME stays as it is: claude and gh find their sign-in through it.
    let configBase: String
    let stateBase: String

    private let overrides: [String: String]

    init(home: String? = nil, env: [String: String] = ProcessInfo.processInfo.environment) {
        let h = home ?? env["HOME"] ?? NSHomeDirectory()
        self.home = h
        self.overrides = env
        self.configBase = Paths.absoluteEnv(env["XDG_CONFIG_HOME"]) ?? h + "/.config"
        self.stateBase = Paths.absoluteEnv(env["XDG_STATE_HOME"]) ?? h + "/.local/state"
    }

    /// An XDG value counts only when it is an absolute path; the XDG spec says to ignore anything else.
    static func absoluteEnv(_ value: String?) -> String? {
        guard let v = value, v.hasPrefix("/") else { return nil }
        return v
    }

    var configDir: String { configBase + "/glidepath" }
    /// GLIDEPATH_CONFIG_FILE and GLIDEPATH_STATE_DIR let the review session find the runner's folders,
    /// since its environment does not carry the XDG variables.
    var configFile: String { Paths.absoluteEnv(overrides["GLIDEPATH_CONFIG_FILE"]) ?? configDir + "/config.toml" }
    var stateDir: String { Paths.absoluteEnv(overrides["GLIDEPATH_STATE_DIR"]) ?? stateBase + "/glidepath" }
    var runsDir: String { stateDir + "/runs" }
    var currentLink: String { stateDir + "/current" }
    var pausedFile: String { stateDir + "/paused" }
    var updateFile: String { stateDir + "/update.json" }
    var lockFile: String { stateDir + "/run.lock" }
    /// The running sweep's process id, which is also its process group: Stop signals the whole group.
    var pidFile: String { stateDir + "/run.pid" }
    /// The tend check's lock, and its process id while it runs (also its process group, so Stop signals its sessions too).
    var tendLockFile: String { stateDir + "/tend.lock" }
    var tendPidFile: String { stateDir + "/tend.pid" }
    var scratchDir: String { stateDir + "/scratch" }
    var skillDir: String { home + "/.claude/skills/glidepath" }
    var appsDir: String { home + "/Applications" }
    var appLink: String { appsDir + "/Glidepath.app" }
    var agentsDir: String { home + "/Library/LaunchAgents" }
    var plistFile: String { agentsDir + "/\(Launchd.label).plist" }
    var tendPlistFile: String { agentsDir + "/\(Launchd.tendLabel).plist" }
    var logFile: String { home + "/Library/Logs/glidepath.log" }
    var tendLogFile: String { home + "/Library/Logs/glidepath-tend.log" }
    var claudeProjectsDir: String { home + "/.claude/projects" }

    func runFile(_ id: String) -> String { runsDir + "/\(id).json" }

    /// The lock every git command that changes one clone or its worktrees takes, so a review and a tend round never
    /// run git in the same clone at once.
    func cloneLock(_ slug: String) -> String {
        stateDir + "/clone-" + slug.replacingOccurrences(of: "/", with: "-") + ".lock"
    }

    /// Expands a leading `~/` against `home`.
    func expand(_ path: String) -> String {
        path.hasPrefix("~/") ? home + String(path.dropFirst(1)) : path
    }
}
