import XCTest
@testable import ReviewRadar

final class TOMLTests: XCTestCase {
    func testScalarsArraysAndComments() throws {
        let doc = try TOML.parse("""
        # top comment
        name = "a \\"quoted\\" value" # trailing
        count = 42
        neg = -3
        on = true
        list = ["x", "y",
          "z",   # inline comment in array
        ]
        """)
        XCTAssertEqual(doc["name"], .string("a \"quoted\" value"))
        XCTAssertEqual(doc["count"], .int(42))
        XCTAssertEqual(doc["neg"], .int(-3))
        XCTAssertEqual(doc["on"], .bool(true))
        XCTAssertEqual(doc["list"], .array([.string("x"), .string("y"), .string("z")]))
    }

    func testTablesAndArraysOfTables() throws {
        let doc = try TOML.parse("""
        [limits]
        max = 3

        [[repo]]
        slug = "a/b"

        [[repo]]
        slug = "c/d"
        extra = 1
        """)
        XCTAssertEqual(doc["limits"], .table(["max": .int(3)]))
        guard case .array(let repos)? = doc["repo"] else { return XCTFail("repo is not an array") }
        XCTAssertEqual(repos, [
            .table(["slug": .string("a/b")]),
            .table(["slug": .string("c/d"), "extra": .int(1)]),
        ])
    }

    func testDottedHeaderCreatesNestedTable() throws {
        let doc = try TOML.parse("[a.b]\nk = 1\n")
        XCTAssertEqual(doc["a"], .table(["b": .table(["k": .int(1)])]))
    }

    func testErrorsCarryLineNumbers() {
        XCTAssertThrowsError(try TOML.parse("a = 1\nb = 2.5\n")) { error in
            XCTAssertEqual((error as? TOMLError)?.line, 2)
        }
        XCTAssertThrowsError(try TOML.parse("a = 1\na = 2\n"))
        XCTAssertThrowsError(try TOML.parse("[t]\n[t]\n"))
        XCTAssertThrowsError(try TOML.parse("s = \"open\n"))
        XCTAssertThrowsError(try TOML.parse("x = 1 2\n"))
    }

    func testCRLFLineEndings() throws {
        let doc = try TOML.parse("a = 1\r\n[t]\r\nb = \"x\"\r\n")
        XCTAssertEqual(doc["a"], .int(1))
        XCTAssertEqual(doc["t"], .table(["b": .string("x")]))
    }

    func testLeadingBOMIsStripped() throws {
        let doc = try TOML.parse("\u{FEFF}a = 2\n")
        XCTAssertEqual(doc["a"], .int(2))
    }
}
