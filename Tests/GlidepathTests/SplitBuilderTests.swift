import XCTest
@testable import Glidepath

@MainActor
final class SplitBuilderTests: XCTestCase {
    /// The fixture's #1270 plan opens valid. A file moves between parts without changing the file set, and emptying a
    /// part is the problem Build waits on.
    func testMovesKeepTheFileSetAndAnEmptyPartIsAProblem() {
        let store = Store(snapshot: WindowFixtures.section("approach", now: WindowFixtures.clock))
        let model = SplitBuilderModel()
        model.open(slug: "lumen/api", n: 1270, title: "feat(certs)", store: store)
        XCTAssertTrue(model.shown)
        XCTAssertNil(model.problem)
        let all = model.changed.count

        model.move("prisma/seed.ts", to: 1)
        XCTAssertNil(model.problem)
        XCTAssertEqual(model.parts.flatMap(\.files).count, all)

        for file in model.parts[1].files { model.move(file, to: 0) }
        XCTAssertEqual(model.problem, "Part 2 has no files")
        XCTAssertEqual(model.parts.flatMap(\.files).count, all)
    }
}
