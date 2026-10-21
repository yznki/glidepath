import XCTest
@testable import Glidepath

/// The shortcut table drives the menus and the ⌘/ sheet, so these tests keep it honest.
final class ShortcutTests: XCTestCase {
    func testEveryActionHasExactlyOneEntry() {
        let actions = Shortcuts.all.map(\.action)
        XCTAssertEqual(actions.count, ShortcutAction.allCases.count)
        XCTAssertEqual(Set(actions), Set(ShortcutAction.allCases))
    }

    func testNoDuplicateKeysWithinAScope() {
        XCTAssertEqual(Shortcuts.conflicts().map { "\($0.0) \($0.1)" }, [])
    }

    func testAlternatesMayShareAKey() {
        XCTAssertEqual(Shortcuts.shortcut(.postReview).glyphs, "⌘↩")
        XCTAssertEqual(Shortcuts.shortcut(.reviewAnyway).glyphs, "⌘↩")
    }

    func testMenuItemsAreTheSpecShortcuts() {
        XCTAssertEqual(Shortcuts.shortcut(.runSweep).glyphs, "⌘R")
        XCTAssertEqual(Shortcuts.shortcut(.stopSweep).glyphs, "⌘.")
        XCTAssertEqual(Shortcuts.shortcut(.togglePause).glyphs, "⇧⌘P")
        XCTAssertEqual(Shortcuts.shortcut(.filterSkipped).glyphs, "⌥⌘4")
        XCTAssertEqual(Shortcuts.shortcut(.shortcuts).glyphs, "⌘/")
        XCTAssertEqual(Shortcuts.shortcut(.togglePopover).glyphs, "⌥⌘G")
    }

    func testEveryMenuHasItems() {
        for menu in ShortcutMenu.allCases where menu != .window {
            XCTAssertFalse(Shortcuts.items(in: menu).isEmpty, menu.rawValue)
        }
    }

    func testColumnsKeepEveryGroupOnce() {
        let groups = Shortcuts.sheetGroups
        let split = Shortcuts.columns(groups)
        XCTAssertEqual((split.left + split.right).map(\.title).sorted(), groups.map(\.title).sorted())
    }

    func testSearchMatchesTitleAndGlyphs() {
        XCTAssertTrue(Shortcuts.filter("⌘r").flatMap(\.items).contains { $0.action == .runSweep })
        XCTAssertTrue(Shortcuts.filter("pause").flatMap(\.items).contains { $0.action == .togglePause })
        XCTAssertTrue(Shortcuts.filter("zzz-nothing").isEmpty)
        XCTAssertEqual(Shortcuts.filter("").count, Shortcuts.sheetGroups.count)
    }

    func testRunSweepIsDisabledWhileRunningAndDuringOnboarding() {
        var s = ShortcutState(configured: true)
        XCTAssertTrue(ShortcutAvailability.enabled(.runSweep, s))
        s.sweepRunning = true
        XCTAssertFalse(ShortcutAvailability.enabled(.runSweep, s))
        XCTAssertTrue(ShortcutAvailability.enabled(.stopSweep, s))
        s = ShortcutState(onboarding: true, configured: true)
        XCTAssertFalse(ShortcutAvailability.enabled(.runSweep, s), "⌘R belongs to Check again during onboarding")
    }

    func testReviewActionsNeedAReviewOnTheReviewsSection() {
        var s = ShortcutState(section: .reviews, reviewSelected: true, reviewCanPost: true)
        XCTAssertTrue(ShortcutAvailability.enabled(.postReview, s))
        XCTAssertFalse(ShortcutAvailability.enabled(.reviewAnyway, s))
        s.section = .repos
        XCTAssertFalse(ShortcutAvailability.enabled(.postReview, s))
    }

    func testPauseTitleFollowsState() {
        XCTAssertEqual(ShortcutAvailability.title(.togglePause, ShortcutState(paused: true)), "Resume Sweeps")
        XCTAssertEqual(ShortcutAvailability.title(.togglePause, ShortcutState()), "Pause Sweeps")
    }
}
