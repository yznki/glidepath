import Foundation

enum Launchd {
    static let label = "dev.glidepath.run"

    /// The LaunchAgent dictionary. `binary` must be the stable path the user installed (not a build folder).
    static func plist(binary: String, schedule: [ScheduleTime], path: String, logFile: String) -> [String: Any] {
        let times: [[String: Any]] = schedule.map { ["Hour": $0.hour, "Minute": $0.minute] }
        return [
            "Label": label,
            "ProgramArguments": [binary, "run", "--scheduled"],
            "StartCalendarInterval": times,
            "EnvironmentVariables": ["PATH": path],
            "StandardOutPath": logFile,
            "StandardErrorPath": logFile,
            "RunAtLoad": false,
        ]
    }

    static func data(binary: String, schedule: [ScheduleTime], path: String, logFile: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: plist(binary: binary, schedule: schedule, path: path, logFile: logFile),
            format: .xml, options: 0)
    }
}

/// Finds gitnexus for the launchd job. A job does not inherit the shell's PATH, so the directory it lives in is added
/// to the job's PATH when `init` or `init --refresh` finds it.
enum GitNexus {
    /// Where gitnexus is commonly installed, after PATH itself.
    static func commonDirectories(home: String) -> [String] {
        [home + "/Library/pnpm", home + "/.local/share/pnpm", home + "/.npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// The full path of gitnexus: on `path`, then in the common folders, then in npm's global bin. nil when none has it.
    static func find(path: String?, home: String) -> String? {
        if let found = Shell.find("gitnexus", path: path) { return found }
        for dir in commonDirectories(home: home) where FileManager.default.isExecutableFile(atPath: dir + "/gitnexus") {
            return dir + "/gitnexus"
        }
        guard let npm = Shell.find("npm", path: path) else { return nil }
        let prefix = Shell.run(npm, ["prefix", "-g"], timeout: 30).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = prefix + "/bin/gitnexus"
        return prefix.isEmpty || !FileManager.default.isExecutableFile(atPath: candidate) ? nil : candidate
    }

    /// `base` with the directory of `gitnexus` appended when it is not already listed. Appended, so the entries
    /// already there keep their order and precedence.
    static func addingDirectory(of gitnexus: String?, to base: String) -> String {
        guard let gitnexus else { return base }
        let dir = (gitnexus as NSString).deletingLastPathComponent
        let entries = base.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard !entries.contains(dir) else { return base }
        return base.isEmpty ? dir : base + ":" + dir
    }

    /// The PATH for the job: `base` plus gitnexus's directory when gitnexus can be found.
    static func jobPath(base: String, home: String) -> String {
        addingDirectory(of: find(path: base, home: home), to: base)
    }
}

/// Pause is a marker file, so the launchd job and the menu bar app agree without talking to each other.
enum Pause {
    static func isPaused(_ paths: Paths) -> Bool {
        FileManager.default.fileExists(atPath: paths.pausedFile)
    }

    /// When the pause started, read from the marker file. nil when not paused or unreadable.
    static func since(_ paths: Paths) -> Date? {
        guard let text = try? String(contentsOfFile: paths.pausedFile, encoding: .utf8) else { return nil }
        let stamp = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "paused ", with: "")
        return ISO8601DateFormatter().date(from: stamp)
    }

    static func set(_ paused: Bool, _ paths: Paths) throws {
        let fm = FileManager.default
        if paused {
            try fm.createDirectory(atPath: paths.stateDir, withIntermediateDirectories: true)
            try Data("paused \(ISO8601DateFormatter().string(from: Date()))\n".utf8)
                .write(to: URL(fileURLWithPath: paths.pausedFile))
        } else if fm.fileExists(atPath: paths.pausedFile) {
            try fm.removeItem(atPath: paths.pausedFile)
        }
    }
}
