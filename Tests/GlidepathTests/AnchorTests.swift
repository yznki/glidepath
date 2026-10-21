import XCTest
@testable import Glidepath

/// Regexes must match the whole string. `$` would also match before a trailing newline, so names with one are refused.
final class AnchorTests: XCTestCase {
    func testTrailingNewlineIsNotAcceptedInNames() {
        XCTAssertFalse(RepoConfig.isValidSlug("acme/api\n"))
        XCTAssertTrue(RepoConfig.isValidSlug("acme/api"))
        let binding = RunBinding(runId: "r", repo: "a/b", scratch: FileManager.default.temporaryDirectory.path,
                                 clone: "/c", dryRun: true)
        XCTAssertThrowsError(try PRCommands.output("x", ["--out": "pr.json\n"], binding, 1))
        XCTAssertThrowsError(try PRCommands.output("x", ["--out": "pr.json\n\n"], binding, 1))
    }
}
