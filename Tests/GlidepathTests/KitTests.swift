import XCTest
@testable import Glidepath

final class KitTests: XCTestCase {
    // MARK: Glide line

    func testEveryStateMapsToItsLine() {
        XCTAssertEqual(LineLook.of(.quiet(next: nil)), LineLook(motion: .breath))
        XCTAssertEqual(LineLook.of(.checking(CheckProgress())), LineLook(motion: .tracer))
        XCTAssertEqual(LineLook.of(.needs(count: 3)), LineLook(beads: 3))
        XCTAssertEqual(LineLook.of(.problem(reason: .signedOut, fix: .signIn)), LineLook(broken: true))
        XCTAssertEqual(LineLook.of(.paused(until: nil)), LineLook(stroke: .dotted))
        XCTAssertEqual(LineLook.of(.holdingBack(reason: .quietHours, resumesAt: nil)), LineLook(stroke: .dotted, dim: true))
    }

    func testBeadsFollowTheOneCountAndStopAtTheCap() {
        XCTAssertEqual(LineLook.of(.needs(count: 1)).beads, 1)
        XCTAssertEqual(LineLook.of(.needs(count: 30)).beads, LineLook.maxBeads)
        XCTAssertEqual(LineLook.of(.needs(count: -1)).beads, 0)
    }

    func testReduceMotionStopsTheBreathAndTheTracer() {
        XCTAssertEqual(LineLook.of(.quiet(next: nil), reduceMotion: true).motion, .still)
        XCTAssertEqual(LineLook.of(.checking(CheckProgress()), reduceMotion: true).motion, .still)
        // The shape still tells the state.
        XCTAssertEqual(LineLook.of(.paused(until: nil), reduceMotion: true).stroke, .dotted)
        XCTAssertTrue(LineLook.of(.problem(reason: .notSetUp, fix: .setUp), reduceMotion: true).broken)
    }

    @MainActor
    func testMenuBarGlyphsAreCachedTemplates() {
        let quiet = GlideGlyph.image(for: .quiet(next: nil))
        XCTAssertTrue(quiet.isTemplate)
        XCTAssertTrue(quiet === GlideGlyph.image(for: .quiet(next: Date())), "same shape, same image object")
        XCTAssertTrue(GlideGlyph.image(for: .needs(count: 2)) === GlideGlyph.image(for: .needs(count: 5)))
        XCTAssertFalse(quiet === GlideGlyph.image(for: .paused(until: nil)))
        let early = GlideGlyph.image(for: .checking(CheckProgress()), phase: 0.1)
        XCTAssertFalse(early === GlideGlyph.image(for: .checking(CheckProgress()), phase: 0.6), "the dot moves")
        XCTAssertTrue(early === GlideGlyph.image(for: .checking(CheckProgress()), phase: 1.1), "and loops")
    }

    // MARK: Hold button

    func testReleaseTimesMeanTapCancelOrDone() {
        XCTAssertEqual(HoldModel.duration, 0.6)
        XCTAssertEqual(HoldModel.release(after: 0.05), .tap)
        XCTAssertEqual(HoldModel.release(after: 0.29), .tap)
        XCTAssertEqual(HoldModel.release(after: 0.3), .cancel)
        XCTAssertEqual(HoldModel.release(after: 0.57), .cancel)
        XCTAssertEqual(HoldModel.release(after: 0.598), .done, "a release a frame short of full still fires")
        XCTAssertEqual(HoldModel.release(after: 0.6), .done)
    }

    @MainActor
    func testATapShowsTheHintAndShakesWithoutActing() {
        let model = HoldModel(), t = Date()
        var acted = 0
        model.press(at: t) { acted += 1 }
        XCTAssertEqual(model.release(at: t.addingTimeInterval(0.1)), .tap)
        XCTAssertTrue(model.showHint)
        XCTAssertEqual(model.shakes, 1)
        XCTAssertEqual(acted, 0)
        XCTAssertFalse(model.isPressed)
    }

    @MainActor
    func testLettingGoEarlyCancels() {
        let model = HoldModel(), t = Date()
        var acted = 0
        model.press(at: t) { acted += 1 }
        XCTAssertEqual(model.release(at: t.addingTimeInterval(0.45)), .cancel)
        XCTAssertFalse(model.showHint)
        XCTAssertEqual(acted, 0)
    }

    @MainActor
    func testAFullHoldActsOnce() {
        let model = HoldModel(), t = Date()
        var acted = 0
        model.press(at: t) { acted += 1 }
        model.fire()
        model.fire()
        XCTAssertEqual(model.release(at: t.addingTimeInterval(0.7)), .done)
        XCTAssertEqual(acted, 1)
    }

    @MainActor
    func testLettingGoAfterTheTimeActsEvenBeforeTheTimer() {
        let model = HoldModel(), t = Date()
        var acted = 0
        model.press(at: t) { acted += 1 }
        XCTAssertEqual(model.release(at: t.addingTimeInterval(0.65)), .done)
        XCTAssertEqual(acted, 1)
    }

    @MainActor
    func testLettingGoAFrameShortOfFullStillActs() {
        let model = HoldModel(), t = Date()
        var acted = 0
        model.press(at: t) { acted += 1 }
        XCTAssertEqual(model.release(at: t.addingTimeInterval(0.598)), .done)
        XCTAssertEqual(acted, 1)
    }

    @MainActor
    func testTheTimerActsAtSixTenths() {
        let model = HoldModel()
        let done = expectation(description: "acted")
        model.press { done.fulfill() }
        wait(for: [done], timeout: 2)
        model.release()
    }

    // MARK: Undo banner

    @MainActor
    func testUndoRunsTheUndoAndNeverCommits() {
        let center = UndoCenter()
        var undone = 0, committed = 0
        center.show("Review discarded.", undoManager: nil, undo: { undone += 1 }, commit: { committed += 1 })
        XCTAssertEqual(center.item?.text, "Review discarded.")
        center.undoNow()
        center.undoNow()
        XCTAssertNil(center.item)
        XCTAssertEqual(undone, 1)
        XCTAssertEqual(committed, 0)
    }

    @MainActor
    func testANewBannerCommitsTheLastOne() {
        let center = UndoCenter()
        var committed: [String] = []
        center.show("One", undoManager: nil, undo: {}, commit: { committed.append("one") })
        center.show("Two", undoManager: nil, undo: {}, commit: { committed.append("two") })
        XCTAssertEqual(committed, ["one"])
        XCTAssertEqual(center.item?.text, "Two")
    }

    @MainActor
    func testCommandZUndoesThroughTheUndoManager() {
        let center = UndoCenter(), manager = UndoManager()
        manager.groupsByEvent = false
        var undone = 0
        manager.beginUndoGrouping()
        center.show("Repo removed.", undoManager: manager, undo: { undone += 1 })
        manager.endUndoGrouping()
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(undone, 1)
        XCTAssertNil(center.item)
    }

    @MainActor
    func testWhenTheBannerGoesUndoIsGone() {
        let center = UndoCenter(), manager = UndoManager()
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        center.show("Repo removed.", undoManager: manager, undo: {})
        manager.endUndoGrouping()
        center.finish()
        XCTAssertFalse(manager.canUndo)
    }
}
