import XCTest
@testable import Glidepath

final class TranscriptTests: XCTestCase {
    func testStreamedAssistantLinesCountOnce() {
        let lines = [
            #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":2,"cache_read_input_tokens":999}}}"#,
            #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":2}}}"#,
            #"{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"type":"user","message":{"content":"hi"}}"#,
        ]
        XCTAssertEqual(Transcript.tokens(lines: lines), 19)
    }

    func testSubagentBriefNamesOnePR() {
        let lines = [
            #"{"type":"user","message":{"content":[{"type":"text","text":"Review PR 412 at reviews/412/"}]}}"#,
        ]
        XCTAssertEqual(Transcript.firstUserText(lines: lines), "Review PR 412 at reviews/412/")
        XCTAssertEqual(Transcript.mentions("Review PR 412 and 1234567"), [412])
        XCTAssertEqual(Transcript.mentions("PRs 7 and 9"), [7, 9])
    }

    func testSubagentTokensSplitAmongNamedPRs() {
        XCTAssertEqual(Transcript.split(10, among: [1, 2, 3]), [1: 4, 2: 3, 3: 3])
        XCTAssertEqual(Transcript.split(10, among: [1, 2, 3]).values.reduce(0, +), 10)
        XCTAssertEqual(Transcript.split(7, among: [42]), [42: 7])
        XCTAssertEqual(Transcript.split(7, among: []), [:])
        XCTAssertEqual(Transcript.split(0, among: [5]), [:])
    }

    func testProjectDirEncodesCwd() {
        let paths = Paths(home: "/fake/home")
        XCTAssertEqual(Transcript.projectDir(paths: paths, cwd: "/fake/home/dev/clone"),
                       "/fake/home/.claude/projects/-fake-home-dev-clone")
        XCTAssertEqual(Transcript.projectDir(paths: paths, cwd: "/fake/home/dev.x/clone"),
                       "/fake/home/.claude/projects/-fake-home-dev-x-clone")
    }

    func testProjectDirResolvesTmpToPrivate() {
        let paths = Paths(home: "/fake/home")
        let dir = Transcript.projectDir(paths: paths, cwd: "/tmp")
        print("PROJECT_DIR /tmp -> \(dir)")
        XCTAssertTrue(dir.contains("-private-tmp"), dir)

        let fm = FileManager.default
        let name = "gp-enc-" + UUID().uuidString
        let fresh = "/tmp/" + name + "/clone"
        defer { try? fm.removeItem(atPath: "/tmp/" + name) }
        try? fm.createDirectory(atPath: fresh, withIntermediateDirectories: true)
        let encoded = Transcript.projectDir(paths: paths, cwd: fresh).components(separatedBy: "/").last ?? ""
        XCTAssertEqual(encoded, "-private-tmp-" + name + "-clone")

        let live = Transcript.projectDir(paths: paths, cwd: "/tmp/gp-live/clone").components(separatedBy: "/").last ?? ""
        print("LIVE_ENCODING /tmp/gp-live/clone -> \(live)")
    }

    func testProjectDirFollowsSymlinkedCwd() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gp-link-" + UUID().uuidString).path
        defer { try? fm.removeItem(atPath: root) }
        try fm.createDirectory(atPath: root + "/real", withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real")
        let paths = Paths(home: "/fake/home")
        XCTAssertEqual(Transcript.projectDir(paths: paths, cwd: root + "/link"),
                       Transcript.projectDir(paths: paths, cwd: root + "/real"))
    }
}
