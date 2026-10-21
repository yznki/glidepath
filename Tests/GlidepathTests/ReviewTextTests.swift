import XCTest
@testable import Glidepath

final class ReviewTextTests: XCTestCase {
    var home: String!
    var paths: Paths!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("rr-reviewtext-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        paths = Paths(home: home, env: ["GLIDEPATH_STATE_DIR": home + "/state"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    func record(posted: String? = nil) -> ReviewTextRecord {
        ReviewTextRecord(event: "REQUEST_CHANGES", body: "Looks off.",
                         comments: [PayloadComment(path: "a.swift", line: 4, side: "RIGHT", body: "Nil here.")],
                         head: "abc123", posted: posted)
    }

    func testWriteThenReadRoundTrips() throws {
        let original = record(posted: "2026-10-21T13:04:00Z")
        try ReviewText.write(original, runId: "run-1", slug: "acme/api", n: 7, paths)
        XCTAssertEqual(ReviewText.read(paths, runId: "run-1", slug: "acme/api", n: 7), original)
    }

    func testDraftWritesPostedAsNull() throws {
        try ReviewText.write(record(), runId: "run-1", slug: "acme/api", n: 7, paths)
        let raw = try String(contentsOfFile: ReviewText.path(paths, runId: "run-1", slug: "acme/api", n: 7), encoding: .utf8)
        XCTAssertTrue(raw.contains("\"posted\" : null"), raw)
        XCTAssertEqual(ReviewText.read(paths, runId: "run-1", slug: "acme/api", n: 7)?.posted, nil)
    }

    func testFileLivesUnderRunAndOwnerNameFolder() {
        XCTAssertEqual(ReviewText.path(paths, runId: "run-1", slug: "acme/api", n: 7),
                       home + "/state/reviews/run-1/acme/api/7.json")
    }

    /// Owner and name are separate segments, so a hyphen in one cannot collide with a slash in the other.
    func testSlugsWithHyphensDoNotCollide() {
        XCTAssertNotEqual(ReviewText.path(paths, runId: "run-1", slug: "a/b-c", n: 1),
                          ReviewText.path(paths, runId: "run-1", slug: "a-b/c", n: 1))
    }

    func testMissingFileReadsAsNil() {
        XCTAssertNil(ReviewText.read(paths, runId: "run-1", slug: "acme/api", n: 7))
    }

    func testPruneRemovesOnlyOldRunFolders() throws {
        let root = paths.stateDir
        let store = RunStore(paths: paths)
        try store.save(RunState.new(id: "old-run", now: now.addingTimeInterval(-91 * day)))
        try store.save(RunState.new(id: "new-run", now: now.addingTimeInterval(-89 * day)))
        for id in ["old-run", "new-run"] {
            try ReviewText.write(record(), runId: id, slug: "acme/api", n: 7, paths)
        }

        ReviewText.prune(root: root, now: now, maxAge: 90 * day)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/reviews/old-run"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/reviews/new-run/acme/api/7.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/runs/old-run.json"), "prune leaves run files alone")
    }
}
