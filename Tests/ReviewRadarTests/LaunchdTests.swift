import XCTest
@testable import ReviewRadar

final class LaunchdTests: XCTestCase {
    func testPlistHasScheduleAndPath() throws {
        let schedule = [ScheduleTime("07:00")!, ScheduleTime("19:15")!]
        let data = try Launchd.data(binary: "/opt/homebrew/bin/review-radar", schedule: schedule,
                                    path: "/usr/bin:/opt/homebrew/bin", logFile: "/tmp/log")
        let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(dict["Label"] as? String, "dev.reviewradar.run")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/opt/homebrew/bin/review-radar", "run", "--scheduled"])
        let env = dict["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(env?["PATH"], "/usr/bin:/opt/homebrew/bin")
        let times = try XCTUnwrap(dict["StartCalendarInterval"] as? [[String: Int]])
        XCTAssertEqual(times, [["Hour": 7, "Minute": 0], ["Hour": 19, "Minute": 15]])
    }

    func testPathsUseHomeOverride() {
        let p = Paths(home: "/tmp/fakehome")
        XCTAssertEqual(p.plistFile, "/tmp/fakehome/Library/LaunchAgents/dev.reviewradar.run.plist")
        XCTAssertEqual(p.configFile, "/tmp/fakehome/.config/review-radar/config.toml")
        XCTAssertEqual(p.appLink, "/tmp/fakehome/Applications/Review Radar.app")
        XCTAssertEqual(p.skillDir, "/tmp/fakehome/.claude/skills/review-radar")
    }

    func testXDGOverridesMoveOnlyReviewRadarFolders() {
        let env = ["XDG_CONFIG_HOME": "/x/cfg", "XDG_STATE_HOME": "/x/state"]
        let p = Paths(home: "/fake/home", env: env)
        XCTAssertEqual(p.configFile, "/x/cfg/review-radar/config.toml")
        XCTAssertEqual(p.stateDir, "/x/state/review-radar")
        XCTAssertEqual(p.claudeProjectsDir, "/fake/home/.claude/projects", "HOME is unchanged for claude")
        XCTAssertEqual(p.plistFile, "/fake/home/Library/LaunchAgents/dev.reviewradar.run.plist")
    }

    func testSessionFindsTheRunnersFolders() {
        let child = Paths(home: "/fake/home", env: [
            "REVIEW_RADAR_STATE_DIR": "/x/state/review-radar", "REVIEW_RADAR_CONFIG_FILE": "/x/cfg/config.toml",
        ])
        XCTAssertEqual(child.stateDir, "/x/state/review-radar")
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
        XCTAssertEqual(p.configFile, "/fake/home/.config/review-radar/config.toml")
        XCTAssertEqual(p.stateDir, "/fake/home/.local/state/review-radar")
    }
}
