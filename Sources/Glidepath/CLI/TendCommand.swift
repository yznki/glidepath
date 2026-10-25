import Foundation

/// The launchd job that runs `glidepath tend` every five minutes. It is installed only while tending is on.
enum TendJob {
    static func install(paths: Paths) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: paths.agentsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (paths.tendLogFile as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        let binary = InitCommand.stableBinary(runningBinary: InitCommand.binaryPath())
        let plist = Launchd.tendPlist(binary: binary, path: InitCommand.jobPath(paths: paths), logFile: paths.tendLogFile)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: paths.tendPlistFile), options: .atomic)
        try InitCommand.loadJob(label: Launchd.tendLabel, plist: paths.tendPlistFile)
    }

    static func remove(paths: Paths) {
        _ = Shell.run("launchctl", ["bootout", "gui/\(getuid())/\(Launchd.tendLabel)"])
        try? FileManager.default.removeItem(atPath: paths.tendPlistFile)
    }
}
