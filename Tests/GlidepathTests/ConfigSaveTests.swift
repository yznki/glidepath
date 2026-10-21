import XCTest
@testable import Glidepath

final class ConfigSaveTests: XCTestCase {
    private var dir: String!
    private var paths: Paths!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "glidepath-save-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/glidepath", withIntermediateDirectories: true)
        paths = Paths(home: dir, env: ["GLIDEPATH_CONFIG_FILE": dir + "/glidepath/config.toml"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func config(posting: Posting = .comment) throws -> Config {
        let base = try Config.parse("""
        schedule = ["07:00"]

        [[repo]]
        slug = "lumen/api"
        clone = "/fake/home/clones/api"
        """, home: dir)
        return try ConfigEditor.setPosting(base, slug: "lumen/api", posting)
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir + "/glidepath").filter { $0.contains(".bak-") }
    }

    // MARK: Backup before the first overwrite

    func testFirstSaveBacksUpHandEditedFileOnce() throws {
        let commented = "# my notes, kept by hand\n" + (try config().render())
        try commented.write(toFile: paths.configFile, atomically: true, encoding: .utf8)
        let session = ConfigSession()

        try ConfigEditor.save(try config(posting: .draft), paths: paths, session: session)
        XCTAssertEqual(try backups().count, 1)
        let backup = try XCTUnwrap(session.backup)
        XCTAssertEqual(try String(contentsOfFile: backup, encoding: .utf8), commented)

        try ConfigEditor.save(try config(posting: .review), paths: paths, session: session)
        XCTAssertEqual(try backups().count, 1, "a second save in the same session makes no new backup")
    }

    func testIdenticalTextMakesNoBackup() throws {
        try (try config()).render().write(toFile: paths.configFile, atomically: true, encoding: .utf8)
        let session = ConfigSession()
        try ConfigEditor.save(try config(posting: .draft), paths: paths, session: session)
        XCTAssertEqual(try backups().count, 0)
        XCTAssertNil(session.backup)
    }

    // MARK: Symlinks

    func testSymlinkedConfigIsWrittenThroughAndStaysALink() throws {
        let real = dir + "/real/config.toml"
        try FileManager.default.createDirectory(atPath: dir + "/real", withIntermediateDirectories: true)
        try (try config()).render().write(toFile: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: paths.configFile, withDestinationPath: real)

        try ConfigEditor.save(try config(posting: .draft), paths: paths, session: ConfigSession())

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: paths.configFile), real)
        XCTAssertEqual(try Config.load(paths).repos.first?.posting, .draft)
        XCTAssertEqual(try Config.parse(String(contentsOfFile: real, encoding: .utf8), home: dir).repos.first?.posting, .draft)
    }

    // MARK: Fresh apply

    func testEditKeepsAChangeMadeOnDiskSinceTheWindowLoaded() throws {
        let onDisk = ConfigEditor.setNotify(try config(), false)
        let result = try ConfigEditor.applyFresh(disk: onDisk) { try ConfigEditor.setPosting($0, slug: "lumen/api", .draft) }
        XCTAssertFalse(result.notify, "the hand-edited notify setting survives the window's edit")
        XCTAssertEqual(result.repos.first?.posting, .draft)
    }

    func testFreshApplyWithoutAConfigWritesNothing() {
        XCTAssertThrowsError(try ConfigEditor.applyFresh(disk: nil) { $0 })
    }
}
