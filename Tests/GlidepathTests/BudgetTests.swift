import XCTest
@testable import Glidepath

final class BudgetTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func run(_ id: String, _ date: Date, tokens: Int) -> RunState {
        var r = RunState.new(id: id, now: date)
        r.tokens = tokens
        return r
    }

    func testUsedSumsOnlyThisCalendarMonth() {
        let may = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23))!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 0, minute: 5))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let runs = [run("a", may, tokens: 900), run("b", june, tokens: 300), run("c", now, tokens: 200)]
        XCTAssertEqual(TokenBudget.used(runs, now: now, calendar: calendar), 500)
        XCTAssertEqual(TokenBudget.used([], now: now, calendar: calendar), 0)
    }

    func testBlocksOnlyWhenBudgetIsSpentAndPausing() throws {
        var c = try Config.parse("monthly_tokens = 1000\n", home: "/h")
        XCTAssertFalse(TokenBudget.blocks(c, used: 999))
        XCTAssertTrue(TokenBudget.blocks(c, used: 1000))
        c.pauseAtBudget = false
        XCTAssertFalse(TokenBudget.blocks(c, used: 5000), "pause_at_budget = false lets sweeps run")
        XCTAssertFalse(TokenBudget.blocks(try Config.parse("", home: "/h"), used: 5000), "0 means no budget")
    }

    func testTimedPauseEndsOnItsOwn() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gp-timed-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let paths = Paths(home: home)
        let until = Date().addingTimeInterval(3600)
        try Pause.set(true, paths, until: until)
        XCTAssertTrue(Pause.isPaused(paths))
        XCTAssertNotNil(Pause.since(paths))
        XCTAssertEqual(Pause.until(paths)?.timeIntervalSince1970 ?? 0, until.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(Pause.isPaused(paths, now: until.addingTimeInterval(1)), "past until the pause is over")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.pausedFile), "and the marker is removed")
    }

    func testOpenPauseHasNoEnd() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gp-open-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let paths = Paths(home: home)
        try Pause.set(true, paths)
        XCTAssertNil(Pause.until(paths))
        XCTAssertTrue(Pause.isPaused(paths, now: Date().addingTimeInterval(86_400 * 365)))
    }
}
