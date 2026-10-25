import XCTest
@testable import Glidepath

final class InitRepoTests: XCTestCase {
    func testEmptyAnswerTakesAValidSuggestion() {
        XCTAssertEqual(InitCommand.repoChoice(answer: "", suggestion: "acme/api"), "acme/api")
        XCTAssertEqual(InitCommand.repoChoice(answer: "  ", suggestion: "acme/api"), "acme/api")
    }

    func testEmptyAnswerWithoutSuggestionIsInvalid() {
        XCTAssertNil(InitCommand.repoChoice(answer: "", suggestion: nil))
    }

    func testAnswerMustBeOwnerName() {
        XCTAssertNil(InitCommand.repoChoice(answer: "acme", suggestion: nil))
        XCTAssertEqual(InitCommand.repoChoice(answer: "acme/api", suggestion: nil), "acme/api")
        XCTAssertEqual(InitCommand.repoChoice(answer: " acme/api ", suggestion: "x/y"), "acme/api")
    }
}
