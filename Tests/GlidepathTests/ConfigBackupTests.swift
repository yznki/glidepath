import XCTest
@testable import Glidepath

final class ConfigBackupTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "glidepath-backup-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    func testNoBackupWhenNoConfigExists() throws {
        let paths = Paths(home: home, env: ["HOME": home])
        XCTAssertNil(try ConfigEditor.backupExisting(paths: paths))
    }

    func testExistingConfigIsCopiedAsideWithTimestamp() throws {
        let paths = Paths(home: home, env: ["HOME": home])
        try FileManager.default.createDirectory(atPath: paths.configDir, withIntermediateDirectories: true)
        try "# mine\n".write(toFile: paths.configFile, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 0)
        let backup = try XCTUnwrap(ConfigEditor.backupExisting(paths: paths, now: now))
        XCTAssertTrue(backup.hasPrefix(paths.configFile + ".bak-"), backup)
        XCTAssertEqual(try String(contentsOfFile: backup, encoding: .utf8), "# mine\n")
        XCTAssertEqual(try String(contentsOfFile: paths.configFile, encoding: .utf8), "# mine\n")
    }

    func testSecondBackupInSameSecondDoesNotOverwrite() throws {
        let paths = Paths(home: home, env: ["HOME": home])
        try FileManager.default.createDirectory(atPath: paths.configDir, withIntermediateDirectories: true)
        try "first\n".write(toFile: paths.configFile, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 0)
        let one = try XCTUnwrap(ConfigEditor.backupExisting(paths: paths, now: now))
        try "second\n".write(toFile: paths.configFile, atomically: true, encoding: .utf8)
        let two = try XCTUnwrap(ConfigEditor.backupExisting(paths: paths, now: now))
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(try String(contentsOfFile: one, encoding: .utf8), "first\n")
        XCTAssertEqual(try String(contentsOfFile: two, encoding: .utf8), "second\n")
    }

    func testSymlinkedConfigIsBackedUpAsItsContents() throws {
        let paths = Paths(home: home, env: ["HOME": home])
        let realDir = home + "/dotfiles"
        try FileManager.default.createDirectory(atPath: realDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: paths.configDir, withIntermediateDirectories: true)
        try "# real\n".write(toFile: realDir + "/config.toml", atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: paths.configFile, withDestinationPath: realDir + "/config.toml")
        let backup = try XCTUnwrap(ConfigEditor.backupExisting(paths: paths, now: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(backup.hasPrefix(paths.configFile + ".bak-"), backup)
        let attrs = try FileManager.default.attributesOfItem(atPath: backup)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(try String(contentsOfFile: backup, encoding: .utf8), "# real\n")
    }
}
