import XCTest
@testable import Glidepath

final class LaunchdTests: XCTestCase {
    func testPlistHasScheduleAndPath() throws {
        let schedule = [ScheduleTime("07:00")!, ScheduleTime("19:15")!]
        let data = try Launchd.data(binary: "/opt/homebrew/bin/glidepath", schedule: schedule,
                                    path: "/usr/bin:/opt/homebrew/bin", logFile: "/tmp/log")
        let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(dict["Label"] as? String, "dev.glidepath.run")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/opt/homebrew/bin/glidepath", "run", "--scheduled"])
        let env = dict["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(env?["PATH"], "/usr/bin:/opt/homebrew/bin")
        let times = try XCTUnwrap(dict["StartCalendarInterval"] as? [[String: Int]])
        XCTAssertEqual(times, [["Hour": 7, "Minute": 0], ["Hour": 19, "Minute": 15]])
    }

    func testPathsUseHomeOverride() {
        let p = Paths(home: "/tmp/fakehome")
        XCTAssertEqual(p.plistFile, "/tmp/fakehome/Library/LaunchAgents/dev.glidepath.run.plist")
        XCTAssertEqual(p.configFile, "/tmp/fakehome/.config/glidepath/config.toml")
        XCTAssertEqual(p.appLink, "/tmp/fakehome/Applications/Glidepath.app")
        XCTAssertEqual(p.skillDir, "/tmp/fakehome/.claude/skills/glidepath")
    }

    func testXDGOverridesMoveOnlyGlidepathFolders() {
        let env = ["XDG_CONFIG_HOME": "/x/cfg", "XDG_STATE_HOME": "/x/state"]
        let p = Paths(home: "/fake/home", env: env)
        XCTAssertEqual(p.configFile, "/x/cfg/glidepath/config.toml")
        XCTAssertEqual(p.stateDir, "/x/state/glidepath")
        XCTAssertEqual(p.claudeProjectsDir, "/fake/home/.claude/projects", "HOME is unchanged for claude")
        XCTAssertEqual(p.plistFile, "/fake/home/Library/LaunchAgents/dev.glidepath.run.plist")
    }

    func testSessionFindsTheRunnersFolders() {
        let child = Paths(home: "/fake/home", env: [
            "GLIDEPATH_STATE_DIR": "/x/state/glidepath", "GLIDEPATH_CONFIG_FILE": "/x/cfg/config.toml",
        ])
        XCTAssertEqual(child.stateDir, "/x/state/glidepath")
        XCTAssertEqual(child.configFile, "/x/cfg/config.toml")
        XCTAssertEqual(child.claudeProjectsDir, "/fake/home/.claude/projects")
    }

    func testGitHubConfigStaysOnRealHomeUnlessSet() {
        let env = ["XDG_CONFIG_HOME": "/x/cfg"]
        XCTAssertEqual(Runner.pinGitHubConfig(env, home: "/fake/home")["GH_CONFIG_DIR"], "/fake/home/.config/gh")
        XCTAssertEqual(Runner.pinGitHubConfig(["GH_CONFIG_DIR": "/mine"], home: "/fake/home")["GH_CONFIG_DIR"], "/mine")
    }

    func testRelativeOrEmptyXDGValuesAreIgnored() {
        let p = Paths(home: "/fake/home", env: ["XDG_CONFIG_HOME": "relative/cfg", "XDG_STATE_HOME": ""])
        XCTAssertEqual(p.configFile, "/fake/home/.config/glidepath/config.toml")
        XCTAssertEqual(p.stateDir, "/fake/home/.local/state/glidepath")
    }

    func testGitNexusDirectoryIsAppendedOnce() {
        XCTAssertEqual(GitNexus.addingDirectory(of: "/opt/x/bin/gitnexus", to: "/usr/bin:/bin"), "/usr/bin:/bin:/opt/x/bin")
        XCTAssertEqual(GitNexus.addingDirectory(of: "/usr/bin/gitnexus", to: "/usr/bin:/bin"), "/usr/bin:/bin")
        XCTAssertEqual(GitNexus.addingDirectory(of: nil, to: "/usr/bin"), "/usr/bin")
        XCTAssertEqual(GitNexus.addingDirectory(of: "/x/gitnexus", to: ""), "/x")
    }

    func testJobPathFindsGitNexusInACommonFolder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rr-gitnexus-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let dir = home + "/Library/pnpm"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let binary = dir + "/gitnexus"
        XCTAssertTrue(FileManager.default.createFile(atPath: binary, contents: Data("#!/bin/sh\n".utf8),
                                                     attributes: [.posixPermissions: 0o755]))
        XCTAssertEqual(GitNexus.find(path: "/usr/bin:/bin", home: home), binary)
        XCTAssertEqual(GitNexus.jobPath(base: "/usr/bin:/bin", home: home), "/usr/bin:/bin:" + dir)
        XCTAssertEqual(GitNexus.jobPath(base: "/usr/bin:/bin:" + dir, home: home), "/usr/bin:/bin:" + dir)
    }
}
