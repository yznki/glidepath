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
