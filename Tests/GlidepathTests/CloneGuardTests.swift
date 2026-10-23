import XCTest
@testable import Glidepath

final class CloneGuardTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = (FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// A folder that looks like a git checkout (a .git directory) without running git.
    func makeCheckout(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path + "/.git", withIntermediateDirectories: true)
    }

    func testOwnedByMarkerPasses() throws {
        let clone = root + "/work/api"
        try makeCheckout(clone)
        try "created by glidepath; safe to delete with the clone\n".write(toFile: RepoClone.markerPath(clone),
                                                                          atomically: true, encoding: .utf8)
        XCTAssertTrue(RepoClone.owns(clone, home: root + "/home"))
        XCTAssertNoThrow(try RepoClone.claim(clone, home: root + "/home"))
    }

    func testLegacyDefaultPathPassesAndGetsMarker() throws {
        let home = root + "/home"
        let clone = ConfigEditor.defaultClone(slug: "acme/api", home: home)
        try makeCheckout(clone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RepoClone.markerPath(clone)))
        XCTAssertNoThrow(try RepoClone.claim(clone, home: home))
        XCTAssertTrue(FileManager.default.fileExists(atPath: RepoClone.markerPath(clone)))
    }

    func testForeignCheckoutThrowsAndIsLeftAlone() throws {
        let home = root + "/home"
        let clone = root + "/work/api"
        try makeCheckout(clone)
        let configPath = clone + "/.git/config"
        let excludePath = clone + "/.git/info/exclude"
        try "[core]\n".write(toFile: configPath, atomically: true, encoding: .utf8)
        let configBefore = try String(contentsOfFile: configPath, encoding: .utf8)

        let repo = RepoConfig(slug: "acme/api", clone: clone)
        XCTAssertThrowsError(try RepoClone.sync(repo, env: [:], home: home)) { error in
            XCTAssertEqual((error as? RunError)?.message, RepoClone.notOwned(clone).message)
            XCTAssertTrue((error as? RunError)?.message.hasPrefix("\(clone) is not a Glidepath clone.") ?? false)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: RepoClone.markerPath(clone)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: excludePath))
        XCTAssertEqual(try String(contentsOfFile: configPath, encoding: .utf8), configBefore)
    }
}
