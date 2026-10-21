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
    var pinSelected = false
    var reviewSelected = false
    var reviewCanPost = false
    var reviewCanDiscard = false
    var reviewIsLarge = false
    /// Onboarding is on its Repos step, where Find focuses the picker's search.
    var repoStepShowing = false
    /// A sheet is up (the ⌘/ sheet, Add Repo, Add Time). Only the window's own close, hide, quit and ⌘/ stay live.
    var sheetOpen = false
}

enum ShortcutAvailability {
    /// What stays live behind a sheet.
    static let sheetAllowed: Set<ShortcutAction> = [.closeWindow, .hide, .quit, .shortcuts]

    static func enabled(_ action: ShortcutAction, _ s: ShortcutState) -> Bool {
        if s.sheetOpen && !sheetAllowed.contains(action) { return false }
        let inReviews = !s.onboarding && s.section == .reviews && s.reviewSelected
        switch action {
        case .showOverview, .showReviews, .showRepos, .showSchedule, .showSettings:
            return !s.onboarding
        case .addRepo:
            // Onboarding has its own repo picker, so Add Repo's sheet is not offered there.
            return !s.onboarding
        case .filterAll, .filterChanges, .filterDrafts, .filterSkipped:
            return !s.onboarding && s.section == .reviews
        case .find:
            // Onboarding's search is on the Repos step only; the Repos section has its own.
            return s.onboarding ? s.repoStepShowing : s.section == .repos
        case .addTime:
            return !s.onboarding && s.section == .schedule
        case .discardDraft:
            return inReviews && s.reviewCanDiscard
        case .removeRepo:
            return !s.onboarding && s.section == .repos && s.repoSelected
        case .deletePin:
            return s.pinSelected && (s.onboarding || s.section == .schedule)
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
        case .reviewAnyway:
            return inReviews && s.reviewIsLarge
        case .openOnGitHub, .copyLink, .copyReviewText:
            return inReviews
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

    /// Edit > Delete: the action for the selection in the current section, or nil when none applies.
    static func contextDelete(_ s: ShortcutState) -> ShortcutAction? {
        [ShortcutAction.discardDraft, .removeRepo, .deletePin].first { enabled($0, s) }
    }

    /// File > New: Add Time in Schedule, Add Repo everywhere else.
    static func contextNew(_ s: ShortcutState) -> ShortcutAction {
        s.section == .schedule && !s.onboarding ? .addTime : .addRepo
    }
}

extension ListKey {
    /// The list key a SwiftUI key press is, or nil for keys a list does not use.
    init?(_ key: KeyEquivalent) {
        switch key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .home: self = .home
        case .end: self = .end
        case .pageUp: self = .pageUp
        case .pageDown: self = .pageDown
        default: return nil
        }
    }
}

extension ShortcutKey {
    /// The table's key for a key press: a named key, or a character lower-cased.
    static func from(_ press: KeyPress) -> ShortcutKey? {
        switch press.key {
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .return: return .returnKey
        case .escape: return .escape
        case .delete: return .delete
        case .space: return .space
        case .tab: return .tab
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .home: return .home
        case .end: return .end
        default:
            guard press.characters.count == 1, let c = press.characters.lowercased().first else { return nil }
            return .character(c)
        }
    }
}

/// Pages the main window's detail scroll view, for Space in a review body. The detail is the wide scroll view; the
/// list beside it is narrow, so the widest one wins.
@MainActor
enum ScrollPager {
    static func pageDown() {
        guard let root = NSApp.keyWindow?.contentView else { return }
        let scrolls = descendants(of: root).compactMap { $0 as? NSScrollView }.filter { $0.bounds.width > 400 }
        guard let widest = scrolls.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
        else { return }
        widest.pageDown(nil)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}

/// Whether a text field has focus. Plain-key shortcuts stay out of the way while it does; ⌘ combos and Esc still work.
@MainActor
enum TextFocus {
    static var isEditing: Bool { NSApp.keyWindow?.firstResponder is NSText }
}

/// What the repo picker's list offers the Edit menu while it has focus: Select All and Select None.
struct RepoPickerActions {
    let selectAll: () -> Void
    let selectNone: () -> Void
}

struct RepoPickerKey: FocusedValueKey {
    typealias Value = RepoPickerActions
}

extension FocusedValues {
    var repoPicker: RepoPickerActions? {
        get { self[RepoPickerKey.self] }
        set { self[RepoPickerKey.self] = newValue }
    }
}

/// What a menu shortcut does while a text field has focus. Plain keys belong to the field; ⌘ combinations are the menus'.
/// Delete-type actions hand their key to the field as a delete, so ⌘⌫ still deletes a word.
enum ShortcutRoute: Equatable {
    case perform, forwardDelete, ignore

    static func route(_ action: ShortcutAction, editing: Bool) -> ShortcutRoute {
        guard editing else { return .perform }
        if [ShortcutAction.discardDraft, .removeRepo, .deletePin].contains(action) { return .forwardDelete }
        // Every ⌘ combination is the menus' and performs (⌘1, ⌘, and ⌘/ included). Keys without ⌘ are the field's.
        let shortcut = Shortcuts.shortcut(action)
        guard shortcut.key != nil else { return .perform }
        return shortcut.modifiers.contains(.command) ? .perform : .ignore
    }
}

/// The Reviews, Repos and Schedule views publish their selection here, so the menus can enable the right items.
@MainActor
final class ShortcutContext: ObservableObject {
    static let shared = ShortcutContext()
    /// The Add Repo and Add Time sheets, set by their views.
    @Published var repoSheetOpen = false
    @Published var timeSheetOpen = false
    @Published var repoSelected = false
    @Published var repoStepShowing = false
    @Published var pinSelected = false
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
        switch ShortcutRoute.route(action, editing: TextFocus.isEditing) {
        case .forwardDelete:
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
            return
        case .ignore:
            return
        case .perform:
            break
        }
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
        case .addTime:
            router.deliver(action, section: .schedule)
        case .find, .reviewRepoNow, .postReview, .discardDraft, .reviewAnyway, .openOnGitHub,
             .copyLink, .copyReviewText, .editRules, .removeRepo, .deletePin:
            router.deliver(action, section: nil)
        case .runSweep: Confirm.run(store)
        case .stopSweep: Confirm.stop(store)
        case .togglePause: store.togglePause()
        case .openLog: store.openLog()
        case .checkUpdates: store.checkForUpdates(manual: true)
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        case .hide: NSApp.hide(nil)
        case .quit:
            // The app delegate waits for a pending schedule save before the app exits.
            NSApp.terminate(nil)
        case .closeWindow: NSApp.keyWindow?.performClose(nil)
        case .minimize: NSApp.keyWindow?.miniaturize(nil)
        case .zoom: NSApp.keyWindow?.zoom(nil)
        case .bringAllToFront: NSApp.arrangeInFront(nil)
        case .shortcuts: router.showShortcuts = true
        default: break
        }
    }
}

/// The menu bar menus, built from `Shortcuts`. Enablement follows `ShortcutAvailability`. File > New and Edit > Delete
/// are context items: their title and action follow the section.
@MainActor
struct GlidepathCommands: Commands {
    @ObservedObject private var router = WindowRouter.shared
    @ObservedObject private var store = Store.shared
    @ObservedObject private var context = ShortcutContext.shared
    @FocusedValue(\.repoPicker) private var picker: RepoPickerActions?

    private var state: ShortcutState {
        ShortcutState(section: router.section, onboarding: router.showOnboarding,
                      sweepRunning: store.snap.running, paused: store.snap.paused,
                      configured: store.snap.config?.repos.isEmpty == false,
                      repoSelected: context.repoSelected, pinSelected: context.pinSelected,
                      reviewSelected: context.reviewSelected, reviewCanPost: context.reviewCanPost,
                      reviewCanDiscard: context.reviewCanDiscard, reviewIsLarge: context.reviewIsLarge,
                      repoStepShowing: context.repoStepShowing,
                      sheetOpen: router.showShortcuts || context.repoSheetOpen || context.timeSheetOpen)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) { item(.about) }
        CommandGroup(after: .appInfo) { item(.checkUpdates) }
        CommandGroup(replacing: .appSettings) { item(.settings) }
        CommandGroup(replacing: .appVisibility) { item(.hide) }
        CommandGroup(replacing: .appTermination) { item(.quit) }

        CommandGroup(replacing: .newItem) { contextNew }
        CommandGroup(replacing: .saveItem) { item(.closeWindow) }

        // Standard Cut, Copy and Paste go to the responder chain; Select All is the picker's when the picker has focus.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) { contextDelete }
        CommandGroup(after: .pasteboard) {
            Button("Select All") {
                if let picker { picker.selectAll() } else { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
            .keyboardShortcut("a", modifiers: .command)
            if let picker {
                Button("Select None") { picker.selectNone() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
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

    /// File > New: one slot, "Add Repo…" or "Add Time…" by section.
    @ViewBuilder
    private var contextNew: some View {
        item(ShortcutAvailability.contextNew(state))
    }

    /// Edit > Delete: "Discard Draft", "Remove Repo…" or "Remove Time" by section; disabled when none applies.
    @ViewBuilder
    private var contextDelete: some View {
        if let action = ShortcutAvailability.contextDelete(state) {
            item(action)
        } else {
            Button("Delete") {}
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(true)
        }
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
