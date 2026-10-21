import XCTest
@testable import ReviewRadar

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

    func testProjectDirEncodesCwd() {
        let paths = Paths(home: "/Users/a")
        XCTAssertEqual(Transcript.projectDir(paths: paths, cwd: "/Users/a/dev/clone"),
                       "/Users/a/.claude/projects/-Users-a-dev-clone")
        XCTAssertEqual(Transcript.projectDir(paths: paths, cwd: "/Users/a/dev.x/clone"),
                       "/Users/a/.claude/projects/-Users-a-dev-x-clone")
    }
}
