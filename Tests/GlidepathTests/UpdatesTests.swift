import XCTest
@testable import Glidepath

final class UpdatesTests: XCTestCase {
    func testSemverOrdering() {
        XCTAssertTrue(Updates.isNewer("1.1.0", than: "1.0.3"))
        XCTAssertTrue(Updates.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(Updates.isNewer("v2.0.0", than: "1.9.9"))
        XCTAssertFalse(Updates.isNewer("1.0.3", than: "1.0.3"))
        XCTAssertFalse(Updates.isNewer("1.0.2", than: "1.0.3"))
    }

    func testBadVersionsMeanNoUpdate() {
        for bad in ["", "1.1", "1.1.x", "1.1.0.1", "latest", "1..0", "-1.0.0", "1.1.99999999999999999999"] {
            XCTAssertNil(Updates.semver(bad), bad)
            XCTAssertFalse(Updates.isNewer(bad, than: "1.0.3"), bad)
            XCTAssertFalse(Updates.isNewer("9.9.9", than: bad), bad)
        }
    }

    func testVersionConstantIsSemverAndMatchesInfoPlist() throws {
        XCTAssertNotNil(Updates.semver(Version.current))
        // make-app.sh overwrites the bundle's version from the constant; the template must not drift from it either.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, Version.current)
    }

    func testParsesLatestReleaseReply() throws {
        let json = """
        {"tag_name": "v1.1.0", "html_url": "https://github.com/yznki/glidepath/releases/tag/v1.1.0",
         "body": "Notes", "draft": false, "prerelease": false}
        """
        let release = try XCTUnwrap(Updates.parseRelease(Data(json.utf8)))
        XCTAssertEqual(release.version, "1.1.0")
        XCTAssertEqual(release.url, "https://github.com/yznki/glidepath/releases/tag/v1.1.0")
        XCTAssertEqual(release.notes, "Notes")
        XCTAssertNil(Updates.parseRelease(Data(#"{"tag_name": "nightly", "html_url": "x"}"#.utf8)))
        XCTAssertNil(Updates.parseRelease(Data("not json".utf8)))
    }

    func testInstallKindFromBinaryPath() {
        XCTAssertEqual(InstallKind.of(binary: "/opt/homebrew/Cellar/glidepath/1.0.2/bin/glidepath"),
                       .homebrew(prefix: "/opt/homebrew"))
        XCTAssertEqual(InstallKind.of(binary: "/usr/local/Cellar/glidepath/1.0.3/bin/glidepath"),
                       .homebrew(prefix: "/usr/local"))
        XCTAssertEqual(InstallKind.of(binary: "/Users/me/dev/glidepath/.build/release/glidepath"), .source)
    }

    func testHomebrewAppLinksThroughOptPath() {
        XCTAssertEqual(InstallKind.appTarget(binary: "/opt/homebrew/Cellar/glidepath/1.0.2/bin/glidepath",
                                             app: "/opt/homebrew/Cellar/glidepath/1.0.2/Glidepath.app"),
                       "/opt/homebrew/opt/glidepath/Glidepath.app")
        let source = "/Users/me/dev/glidepath/build/Glidepath.app"
        XCTAssertEqual(InstallKind.appTarget(binary: "/Users/me/dev/glidepath/.build/release/glidepath", app: source), source)
    }

    func testCacheRoundTripAndDueness() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gp-updates-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let paths = Paths(home: home, env: [:])
        XCTAssertNil(Updates.cached(paths))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = UpdateCache(checked: now, latest: "1.1.0", url: "https://example.test/release")
        try Updates.store(cache, paths)
        XCTAssertEqual(Updates.cached(paths), cache)
        XCTAssertTrue(Updates.isDue(nil, now: now, maxAge: Updates.maxAge))
        XCTAssertFalse(Updates.isDue(cache, now: now.addingTimeInterval(60), maxAge: Updates.maxAge))
        XCTAssertTrue(Updates.isDue(cache, now: now.addingTimeInterval(Updates.maxAge + 1), maxAge: Updates.maxAge))
    }
}
