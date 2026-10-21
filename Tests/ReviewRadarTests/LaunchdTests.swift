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
}
