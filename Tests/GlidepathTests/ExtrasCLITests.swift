import XCTest
@testable import Glidepath

final class ExtrasCLITests: XCTestCase {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A UTC date in October 2026.
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Linear key

    func testLinearKeyShape() {
        XCTAssertTrue(LinearKey.valid("lin_api_abc-123456"))
        XCTAssertFalse(LinearKey.valid("short"))
        XCTAssertFalse(LinearKey.valid("has space in it"))
        XCTAssertFalse(LinearKey.valid("quote\"inside-key"))
        XCTAssertFalse(LinearKey.valid(String(repeating: "a", count: 201)))
    }

    /// A bad key is refused before any Keychain call, so this never touches the login Keychain.
    func testSaveRefusesBadKeyWithoutRunningSecurity() {
        XCTAssertThrowsError(try LinearKey.save("bad key\"; rm -rf ~"))
    }

    func testCommentPostedReadsSuccess() throws {
        XCTAssertTrue(Linear.commentPosted(Data(#"{"data":{"commentCreate":{"success":true}}}"#.utf8)))
        XCTAssertFalse(Linear.commentPosted(Data(#"{"data":{"commentCreate":{"success":false}}}"#.utf8)))
        XCTAssertFalse(Linear.commentPosted(Data(#"{"errors":[{"message":"nope"}]}"#.utf8)))
    }
}
