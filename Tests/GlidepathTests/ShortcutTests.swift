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

    func testFileNewIsAddTimeInScheduleAndAddRepoElsewhere() {
        XCTAssertEqual(ShortcutAvailability.contextNew(ShortcutState(section: .schedule)), .addTime)
        XCTAssertEqual(ShortcutAvailability.contextNew(ShortcutState(section: .repos)), .addRepo)
        XCTAssertEqual(ShortcutAvailability.contextNew(ShortcutState(section: .reviews)), .addRepo)
        XCTAssertEqual(ShortcutAvailability.title(.addTime, ShortcutState()), "Add Time…")
    }

    func testEditDeleteFollowsTheSelection() {
        XCTAssertNil(ShortcutAvailability.contextDelete(ShortcutState(section: .repos)))
        XCTAssertEqual(ShortcutAvailability.contextDelete(ShortcutState(section: .repos, repoSelected: true)), .removeRepo)
        XCTAssertEqual(ShortcutAvailability.contextDelete(ShortcutState(section: .schedule, pinSelected: true)), .deletePin)
        XCTAssertNil(ShortcutAvailability.contextDelete(ShortcutState(section: .schedule)))
        XCTAssertEqual(ShortcutAvailability.contextDelete(ShortcutState(section: .reviews, reviewSelected: true,
                                                                        reviewCanDiscard: true)), .discardDraft)
        XCTAssertNil(ShortcutAvailability.contextDelete(ShortcutState(section: .reviews, reviewSelected: true)))
    }

    func testRemoveTimeInOnboardingNeedsAPin() {
        XCTAssertTrue(ShortcutAvailability.enabled(.deletePin, ShortcutState(onboarding: true, pinSelected: true)))
        XCTAssertFalse(ShortcutAvailability.enabled(.deletePin, ShortcutState(onboarding: true)))
    }

    func testPinKeysAreLookedUpInTheTable() {
        func pin(_ key: ShortcutKey, _ mods: ShortcutModifiers = []) -> ShortcutAction? {
            Shortcuts.action(key: key, modifiers: mods, scope: .schedule)
        }
        XCTAssertEqual(pin(.leftArrow), .selectPrevPin)
        XCTAssertEqual(pin(.rightArrow), .selectNextPin)
        XCTAssertEqual(pin(.leftArrow, .option), .nudgeEarlier)
        XCTAssertEqual(pin(.rightArrow, .option), .nudgeLater)
        XCTAssertEqual(pin(.leftArrow, [.shift, .option]), .nudgeEarlierHour)
        XCTAssertEqual(pin(.upArrow), .pinLater)
        XCTAssertEqual(pin(.downArrow), .pinEarlier)
        XCTAssertEqual(pin(.upArrow, .shift), .pinLaterHour)
        XCTAssertEqual(pin(.downArrow, .shift), .pinEarlierHour)
        XCTAssertNil(pin(.upArrow, .command))
    }

    func testPinMinutesMatchTheirDirection() {
        XCTAssertEqual(ShortcutAction.pinLater.pinMinutes, 15)
        XCTAssertEqual(ShortcutAction.nudgeEarlier.pinMinutes, -15)
        XCTAssertEqual(ShortcutAction.pinLaterHour.pinMinutes, 60)
        XCTAssertEqual(ShortcutAction.nudgeEarlierHour.pinMinutes, -60)
        XCTAssertNil(ShortcutAction.selectNextPin.pinMinutes)
    }

    func testUndoIsTheStandardEditMenuItem() {
        // The ⌘Z handler is gone: undo belongs to the window's undo manager and the standard Edit menu.
        XCTAssertNil(Shortcuts.all.first { $0.key == .character("z") && $0.modifiers == .command })
    }
}

final class ShortcutGuardTests: XCTestCase {
    func testSheetLeavesOnlyCloseHideQuitAndShortcutsLive() {
        var s = ShortcutState(section: .repos, repoSelected: true)
        s.sheetOpen = true
        XCTAssertFalse(ShortcutAvailability.enabled(.addRepo, s))
        XCTAssertFalse(ShortcutAvailability.enabled(.showOverview, s))
        XCTAssertFalse(ShortcutAvailability.enabled(.runSweep, s))
        XCTAssertFalse(ShortcutAvailability.enabled(.find, s))
        XCTAssertTrue(ShortcutAvailability.enabled(.closeWindow, s))
        XCTAssertTrue(ShortcutAvailability.enabled(.hide, s))
        XCTAssertTrue(ShortcutAvailability.enabled(.quit, s))
        XCTAssertTrue(ShortcutAvailability.enabled(.shortcuts, s))
    }

    func testWhileEditingOnlyCommandLettersPerform() {
        XCTAssertEqual(ShortcutRoute.route(.find, editing: true), .perform)
        XCTAssertEqual(ShortcutRoute.route(.closeWindow, editing: true), .perform)
        XCTAssertEqual(ShortcutRoute.route(.stopSweep, editing: true), .ignore)
        XCTAssertEqual(ShortcutRoute.route(.shortcuts, editing: true), .ignore)
        XCTAssertEqual(ShortcutRoute.route(.settings, editing: true), .ignore)
        XCTAssertEqual(ShortcutRoute.route(.postReview, editing: true), .ignore)
    }

    func testDeleteWhileEditingGoesToTheFieldAsADelete() {
        for action in [ShortcutAction.discardDraft, .removeRepo, .deletePin] {
            XCTAssertEqual(ShortcutRoute.route(action, editing: true), .forwardDelete, "\(action)")
        }
        XCTAssertEqual(ShortcutRoute.route(.discardDraft, editing: false), .perform)
    }
}
