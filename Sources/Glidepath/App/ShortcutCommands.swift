import SwiftUI
import AppKit

/// What the menus need to know to enable or disable their items. Pure, so the rules are testable.
struct ShortcutState: Equatable {
    var section: WindowSection = .overview
    var onboarding = false
    var sweepRunning = false
    var paused = false
    var configured = true
    var repoSelected = false
    var reviewSelected = false
    var reviewCanPost = false
    var reviewCanDiscard = false
    var reviewIsLarge = false
}

enum ShortcutAvailability {
    static func enabled(_ action: ShortcutAction, _ s: ShortcutState) -> Bool {
        let inReviews = !s.onboarding && s.section == .reviews && s.reviewSelected
        switch action {
        case .showOverview, .showReviews, .showRepos, .showSchedule, .showSettings:
            return !s.onboarding
        case .filterAll, .filterChanges, .filterDrafts, .filterSkipped:
            return !s.onboarding && s.section == .reviews
        case .find:
            return s.onboarding || s.section == .repos
        case .runSweep:
            return !s.sweepRunning && !s.onboarding && s.configured
        case .stopSweep:
            return s.sweepRunning
        case .togglePause:
            return s.configured && !s.onboarding
        case .reviewRepoNow:
            return s.section == .repos && s.repoSelected && s.configured && !s.onboarding && !s.sweepRunning
        case .postReview:
            return inReviews && s.reviewCanPost
        case .discardDraft:
            return inReviews && s.reviewCanDiscard
        case .reviewAnyway:
            return inReviews && s.reviewIsLarge
        case .openOnGitHub, .copyLink, .copyReviewText:
            return inReviews
        case .openLog, .addRepo, .closeWindow, .settings, .about, .checkUpdates, .hide, .quit,
             .minimize, .zoom, .bringAllToFront, .shortcuts:
            return true
        default:
            return true
        }
    }

    /// The menu title for an item whose name depends on state.
    static func title(_ action: ShortcutAction, _ s: ShortcutState) -> String {
        switch action {
        case .togglePause: return s.paused ? "Resume Sweeps" : "Pause Sweeps"
        default: return Shortcuts.shortcut(action).title
        }
    }
}

/// Whether a text field has focus. Plain-key shortcuts stay out of the way while it does; ⌘ combos and Esc still work.
@MainActor
enum TextFocus {
    static var isEditing: Bool { NSApp.keyWindow?.firstResponder is NSText }
}

/// The Reviews and Repos views publish their selection here, so the menus can enable the right items.
@MainActor
final class ShortcutContext: ObservableObject {
    static let shared = ShortcutContext()
    @Published var repoSelected = false
    @Published var reviewSelected = false
    @Published var reviewCanPost = false
    @Published var reviewCanDiscard = false
    @Published var reviewIsLarge = false

    func setReview(_ row: ReviewRow?) {
        reviewSelected = row != nil
        reviewCanPost = row?.draft ?? false
        reviewCanDiscard = row?.draft ?? false
        reviewIsLarge = row?.tooLarge ?? false
    }
}

/// Runs a menu action. Section changes go through the router; actions a view owns are handed over as `pending`.
@MainActor
enum ShortcutDispatch {
    static func perform(_ action: ShortcutAction, router: WindowRouter = .shared, store: Store = .shared) {
        switch action {
        case .showOverview: router.open(.overview)
        case .showReviews: router.open(.reviews)
        case .showRepos: router.open(.repos)
        case .showSchedule: router.open(.schedule)
        case .showSettings, .settings: router.open(.settings)
        case .filterAll, .filterChanges, .filterDrafts, .filterSkipped:
            router.deliver(action, section: .reviews)
        case .addRepo:
            router.deliver(action, section: .repos)
        case .find, .reviewRepoNow, .postReview, .discardDraft, .reviewAnyway, .openOnGitHub,
             .copyLink, .copyReviewText, .editRules, .removeRepo:
            router.deliver(action, section: nil)
        case .runSweep: store.runNow()
        case .stopSweep: store.stopRun()
        case .togglePause: store.togglePause()
        case .openLog: store.openLog()
        case .checkUpdates: store.checkForUpdates(manual: true)
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        case .hide: NSApp.hide(nil)
        case .quit: NSApp.terminate(nil)
        case .closeWindow: NSApp.keyWindow?.performClose(nil)
        case .minimize: NSApp.keyWindow?.miniaturize(nil)
        case .zoom: NSApp.keyWindow?.zoom(nil)
        case .bringAllToFront: NSApp.arrangeInFront(nil)
        case .shortcuts: router.showShortcuts = true
        default: break
        }
    }
}

/// The menu bar menus, built from `Shortcuts`. Menu enablement follows `ShortcutAvailability`.
@MainActor
struct GlidepathCommands: Commands {
    @ObservedObject private var router = WindowRouter.shared
    @ObservedObject private var store = Store.shared
    @ObservedObject private var context = ShortcutContext.shared

    private var state: ShortcutState {
        ShortcutState(section: router.section, onboarding: router.showOnboarding,
                      sweepRunning: store.snap.running, paused: store.snap.paused,
                      configured: store.snap.config?.repos.isEmpty == false,
                      repoSelected: context.repoSelected, reviewSelected: context.reviewSelected,
                      reviewCanPost: context.reviewCanPost, reviewCanDiscard: context.reviewCanDiscard,
                      reviewIsLarge: context.reviewIsLarge)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) { item(.about) }
        CommandGroup(after: .appInfo) { item(.checkUpdates) }
        CommandGroup(replacing: .appSettings) { item(.settings) }
        CommandGroup(replacing: .appVisibility) { item(.hide) }
        CommandGroup(replacing: .appTermination) { item(.quit) }

        CommandGroup(replacing: .newItem) { item(.addRepo) }
        CommandGroup(replacing: .saveItem) { item(.closeWindow) }

        CommandGroup(after: .textEditing) { item(.find) }

        CommandGroup(before: .sidebar) {
            ForEach(Shortcuts.items(in: .view).filter { $0.action.isSection }, id: \.action) { item($0.action) }
            Divider()
            ForEach(Shortcuts.items(in: .view).filter { !$0.action.isSection }, id: \.action) { item($0.action) }
        }

        CommandMenu("Sweep") {
            ForEach(Shortcuts.items(in: .sweep), id: \.action) { item($0.action) }
        }
        CommandMenu("Review") {
            ForEach(Shortcuts.items(in: .review), id: \.action) { item($0.action) }
        }

        CommandGroup(replacing: .windowArrangement) {
            ForEach(Shortcuts.items(in: .window), id: \.action) { item($0.action) }
        }
        CommandGroup(replacing: .help) { item(.shortcuts) }
    }

    /// One menu item: its title and key come from the table, its state from `state`.
    @ViewBuilder
    private func item(_ action: ShortcutAction) -> some View {
        let shortcut = Shortcuts.shortcut(action)
        let button = Button(ShortcutAvailability.title(action, state)) {
            ShortcutDispatch.perform(action)
        }
        .disabled(!ShortcutAvailability.enabled(action, state))
        if let key = shortcut.key {
            button.keyboardShortcut(key.keyEquivalent, modifiers: shortcut.modifiers.eventModifiers)
        } else {
            button
        }
    }
}

extension ShortcutAction {
    /// The section entries in View: Overview through Settings.
    var isSection: Bool {
        switch self {
        case .showOverview, .showReviews, .showRepos, .showSchedule, .showSettings: return true
        default: return false
        }
    }
}
