import SwiftUI

/// Every keyboard shortcut in the app. The menu bar menus and the ⌘/ sheet both read this table, so they cannot drift.
/// Menu items carry a `menu`; the rest are handled by the view named by `scope` and appear only in the sheet.
enum ShortcutAction: String, CaseIterable {
    // Glidepath
    case about, checkUpdates, settings, hide, quit
    // File
    case addRepo, addTime, closeWindow
    // Edit
    case find, discardDraft, removeRepo, deletePin
    // View
    case showOverview, showReviews, showRepos, showSchedule, showSettings
    // Sweep
    case runSweep, stopSweep, togglePause, reviewRepoNow, openLog
    // Review
    case postReview, reviewAnyway, openOnGitHub, copyLink, copyReviewText
    // Window
    case minimize, zoom, bringAllToFront
    // Help
    case shortcuts
    // Repos detail
    case editRules
    // Schedule: pins are chosen with ← →, and moved with ↑ ↓ or ⌥← ⌥→ (⇧ for the hour).
    case selectPrevPin, selectNextPin
    case pinLater, pinEarlier, pinLaterHour, pinEarlierHour
    case nudgeLater, nudgeEarlier, nudgeLaterHour, nudgeEarlierHour
    // Onboarding
    case primary, back, toggleRow, selectAllRows, selectNoRows, checkAgain
    // Popover
    case popoverOpen, popoverRun, popoverStop, popoverSettings, popoverClose
    // Global
    case togglePopover
}

/// The menus, in menu bar order, and the sheet's groups for them.
enum ShortcutMenu: String, CaseIterable {
    case glidepath = "Glidepath", file = "File", edit = "Edit", view = "View", sweep = "Sweep", review = "Review"
    case window = "Window", help = "Help"
}

/// Where a shortcut applies. Menu items are `.menu`: their menus are enabled or disabled by `ShortcutAvailability`.
enum ShortcutScope: String, CaseIterable {
    case menu, lists, repos, schedule, onboarding, popover, global
}

/// A key on the keyboard, mapped to SwiftUI's `KeyEquivalent` for the menus and printed as a glyph in the sheet.
enum ShortcutKey: Equatable {
    case character(Character)
    case returnKey, escape, delete, space, tab
    case upArrow, downArrow, leftArrow, rightArrow, pageUp, pageDown, home, end

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .character(let c): return KeyEquivalent(c)
        case .returnKey: return .return
        case .escape: return .escape
        case .delete: return .delete
        case .space: return .space
        case .tab: return .tab
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .home: return .home
        case .end: return .end
        }
    }

    var glyph: String {
        switch self {
        case .character(let c): return String(c).uppercased()
        case .returnKey: return "↩"
        case .escape: return "Esc"
        case .delete: return "⌫"
        case .space: return "Space"
        case .tab: return "⇥"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .home: return "Home"
        case .end: return "End"
        }
    }
}

/// Modifier keys, printed in the macOS order ⌃⌥⇧⌘.
struct ShortcutModifiers: OptionSet {
    let rawValue: Int
    static let control = ShortcutModifiers(rawValue: 1)
    static let option = ShortcutModifiers(rawValue: 2)
    static let shift = ShortcutModifiers(rawValue: 4)
    static let command = ShortcutModifiers(rawValue: 8)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ modifiers: EventModifiers) {
        var out: ShortcutModifiers = []
        if modifiers.contains(.control) { out.insert(.control) }
        if modifiers.contains(.option) { out.insert(.option) }
        if modifiers.contains(.shift) { out.insert(.shift) }
        if modifiers.contains(.command) { out.insert(.command) }
        self = out
    }

    var eventModifiers: EventModifiers {
        var out: EventModifiers = []
        if contains(.control) { out.insert(.control) }
        if contains(.option) { out.insert(.option) }
        if contains(.shift) { out.insert(.shift) }
        if contains(.command) { out.insert(.command) }
        return out
    }

    var glyphs: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

extension ShortcutAction {
    /// How far a pin moves for a move action, in minutes. Nil for every other action.
    var pinMinutes: Int? {
        switch self {
        case .pinLater, .nudgeLater: return PinNudge.quarter
        case .pinEarlier, .nudgeEarlier: return -PinNudge.quarter
        case .pinLaterHour, .nudgeLaterHour: return 60
        case .pinEarlierHour, .nudgeEarlierHour: return -60
        default: return nil
        }
    }
}

/// One row of the table.
struct Shortcut: Identifiable, Equatable {
    let action: ShortcutAction
    let title: String
    let key: ShortcutKey?
    var modifiers: ShortcutModifiers = []
    var scope: ShortcutScope = .menu
    var menu: ShortcutMenu?
    /// Two entries may share a combination only when each names the other: they are enabled in different states.
    var alternateOf: ShortcutAction?
    /// A context item: the menu slot shows whichever contextual action applies (Edit > Delete, File > New), so several
    /// entries may share its combination.
    var contextual = false
    /// Where the item applies, shown in the sheet beside its name.
    var note: String?

    var id: ShortcutAction { action }
    /// "⌘R", "⌥⌘1", "⇧⌘P", "⌘↩". Empty when the action has no key.
    var glyphs: String { key.map { modifiers.glyphs + $0.glyph } ?? "" }
}

/// The one table. Order here is the order in the menus and the sheet.
enum Shortcuts {
    static let all: [Shortcut] = [
        Shortcut(action: .about, title: "About Glidepath", key: nil, menu: .glidepath),
        Shortcut(action: .checkUpdates, title: "Check for Updates…", key: nil, menu: .glidepath),
        Shortcut(action: .settings, title: "Settings…", key: .character(","), modifiers: .command, menu: .glidepath),
        Shortcut(action: .hide, title: "Hide Glidepath", key: .character("h"), modifiers: .command, menu: .glidepath),
        Shortcut(action: .quit, title: "Quit Glidepath", key: .character("q"), modifiers: .command, menu: .glidepath),

        Shortcut(action: .addRepo, title: "Add Repo…", key: .character("n"), modifiers: .command, menu: .file,
                 contextual: true, note: "Everywhere but Schedule"),
        Shortcut(action: .addTime, title: "Add Time…", key: .character("n"), modifiers: .command, menu: .file,
                 contextual: true, note: "Schedule"),
        Shortcut(action: .closeWindow, title: "Close Window", key: .character("w"), modifiers: .command, menu: .file),

        Shortcut(action: .discardDraft, title: "Discard Draft", key: .delete, modifiers: .command, menu: .edit,
                 contextual: true, note: "Reviews, a held draft"),
        Shortcut(action: .removeRepo, title: "Remove Repo…", key: .delete, modifiers: .command, menu: .edit,
                 contextual: true, note: "Repos"),
        Shortcut(action: .deletePin, title: "Remove Time", key: .delete, modifiers: .command, menu: .edit,
                 contextual: true, note: "Schedule, pin selected"),
        Shortcut(action: .find, title: "Find", key: .character("f"), modifiers: .command, menu: .edit,
                 note: "Repos, onboarding"),

        Shortcut(action: .showOverview, title: "Now", key: .character("1"), modifiers: .command, menu: .view),
        Shortcut(action: .showReviews, title: "History", key: .character("2"), modifiers: .command, menu: .view),
        Shortcut(action: .showRepos, title: "Repos", key: .character("3"), modifiers: .command, menu: .view),
        Shortcut(action: .showSchedule, title: "Schedule", key: .character("4"), modifiers: .command, menu: .view),
        Shortcut(action: .showSettings, title: "Settings", key: .character("5"), modifiers: .command, menu: .view),

        Shortcut(action: .runSweep, title: "Run Sweep Now", key: .character("r"), modifiers: .command, menu: .sweep),
        Shortcut(action: .stopSweep, title: "Stop Sweep", key: .character("."), modifiers: .command, menu: .sweep),
        Shortcut(action: .togglePause, title: "Pause Sweeps", key: .character("p"), modifiers: [.shift, .command],
                 menu: .sweep),
        Shortcut(action: .reviewRepoNow, title: "Review This Repo Now", key: .character("r"),
                 modifiers: [.shift, .command], menu: .sweep),
        Shortcut(action: .openLog, title: "Open Log", key: .character("l"), modifiers: [.option, .command], menu: .sweep),

        Shortcut(action: .postReview, title: "Post Review", key: .returnKey, modifiers: .command, menu: .review),
        Shortcut(action: .reviewAnyway, title: "Review Anyway", key: .returnKey, modifiers: .command, menu: .review,
                 alternateOf: .postReview),
        Shortcut(action: .openOnGitHub, title: "Open on GitHub", key: .character("o"), modifiers: .command,
                 menu: .review),
        Shortcut(action: .copyLink, title: "Copy Link", key: .character("c"), modifiers: [.shift, .command],
                 menu: .review),
        Shortcut(action: .copyReviewText, title: "Copy Review Text", key: .character("c"),
                 modifiers: [.option, .command], menu: .review),

        Shortcut(action: .minimize, title: "Minimize", key: .character("m"), modifiers: .command, menu: .window),
        Shortcut(action: .zoom, title: "Zoom", key: nil, menu: .window),
        Shortcut(action: .bringAllToFront, title: "Bring All to Front", key: nil, menu: .window),

        Shortcut(action: .shortcuts, title: "Keyboard Shortcuts", key: .character("/"), modifiers: .command, menu: .help),

        // Views: these are handled by the view and appear only in the sheet.
        Shortcut(action: .editRules, title: "Edit rules file", key: .character("e"), modifiers: .command, scope: .repos),
        Shortcut(action: .selectPrevPin, title: "Select the previous pin", key: .leftArrow, scope: .schedule),
        Shortcut(action: .selectNextPin, title: "Select the next pin", key: .rightArrow, scope: .schedule),
        Shortcut(action: .nudgeEarlier, title: "Move pin 15 min earlier", key: .leftArrow, modifiers: .option,
                 scope: .schedule),
        Shortcut(action: .nudgeLater, title: "Move pin 15 min later", key: .rightArrow, modifiers: .option,
                 scope: .schedule),
        Shortcut(action: .nudgeEarlierHour, title: "Move pin 1 h earlier", key: .leftArrow,
                 modifiers: [.shift, .option], scope: .schedule),
        Shortcut(action: .nudgeLaterHour, title: "Move pin 1 h later", key: .rightArrow,
                 modifiers: [.shift, .option], scope: .schedule),
        Shortcut(action: .pinLater, title: "Move pin 15 min later", key: .upArrow, scope: .schedule),
        Shortcut(action: .pinEarlier, title: "Move pin 15 min earlier", key: .downArrow, scope: .schedule),
        Shortcut(action: .pinLaterHour, title: "Move pin 1 h later", key: .upArrow, modifiers: .shift, scope: .schedule),
        Shortcut(action: .pinEarlierHour, title: "Move pin 1 h earlier", key: .downArrow, modifiers: .shift,
                 scope: .schedule),
        Shortcut(action: .primary, title: "Primary step button", key: .returnKey, modifiers: .command, scope: .onboarding),
        Shortcut(action: .back, title: "Back", key: .character("["), modifiers: .command, scope: .onboarding),
        Shortcut(action: .toggleRow, title: "Toggle the selected row", key: .space, scope: .onboarding),
        Shortcut(action: .selectAllRows, title: "Select all visible repos", key: .character("a"), modifiers: .command,
                 scope: .onboarding),
        Shortcut(action: .selectNoRows, title: "Select none", key: .character("a"),
                 modifiers: [.shift, .command], scope: .onboarding),
        Shortcut(action: .checkAgain, title: "Check again", key: .character("r"), modifiers: .command,
                 scope: .onboarding),
        Shortcut(action: .popoverOpen, title: "Open Glidepath window", key: .character("o"), modifiers: .command,
                 scope: .popover),
        Shortcut(action: .popoverRun, title: "Run sweep now", key: .character("r"), modifiers: .command, scope: .popover),
        Shortcut(action: .popoverStop, title: "Stop sweep", key: .character("."), modifiers: .command, scope: .popover),
        Shortcut(action: .popoverSettings, title: "Settings", key: .character(","), modifiers: .command, scope: .popover),
        Shortcut(action: .popoverClose, title: "Close popover", key: .escape, scope: .popover),
        Shortcut(action: .togglePopover, title: "Open or close the menu bar popover", key: .character("g"),
                 modifiers: [.option, .command], scope: .global),
    ]

    static func shortcut(_ action: ShortcutAction) -> Shortcut {
        guard let s = all.first(where: { $0.action == action }) else { fatalError("no shortcut for \(action)") }
        return s
    }

    /// The first entry for a key in a scope, the way the view's key handling looks keys up.
    static func action(key: ShortcutKey, modifiers: ShortcutModifiers, scope: ShortcutScope) -> ShortcutAction? {
        all.first { $0.scope == scope && $0.key == key && $0.modifiers == modifiers }?.action
    }

    /// The menu's items, in table order.
    static func items(in menu: ShortcutMenu) -> [Shortcut] {
        all.filter { $0.menu == menu }
    }

    /// The items for one scope, in table order.
    static func items(scope: ShortcutScope) -> [Shortcut] {
        all.filter { $0.scope == scope }
    }

    /// The sheet's groups: the menus first, in menu order, then each view scope. Items without a key are left out.
    static var sheetGroups: [(title: String, items: [Shortcut])] {
        let menus = ShortcutMenu.allCases.map { ($0.rawValue, items(in: $0).filter { $0.key != nil }) }
        let views: [(String, ShortcutScope)] = [("Lists", .lists), ("Repos", .repos), ("Schedule", .schedule),
                                                ("Onboarding", .onboarding), ("Popover", .popover), ("Global", .global)]
        return menus.filter { !$0.1.isEmpty } + views.map { ($0.0, items(scope: $0.1)) }.filter { !$0.1.isEmpty }
    }

    /// Two entries that share a key combination within one scope, other than alternates of each other.
    static func conflicts() -> [(ShortcutAction, ShortcutAction)] {
        var out: [(ShortcutAction, ShortcutAction)] = []
        for scope in ShortcutScope.allCases {
            let keyed = items(scope: scope).filter { $0.key != nil }
            for (i, a) in keyed.enumerated() {
                for b in keyed[(i + 1)...] where a.glyphs == b.glyphs {
                    if a.alternateOf == b.action || b.alternateOf == a.action { continue }
                    if a.contextual && b.contextual { continue }
                    out.append((a.action, b.action))
                }
            }
        }
        return out
    }

    /// Splits groups into two columns, each group whole, filling the shorter column first.
    static func columns(_ groups: [(title: String, items: [Shortcut])])
        -> (left: [(title: String, items: [Shortcut])], right: [(title: String, items: [Shortcut])]) {
        var left: [(title: String, items: [Shortcut])] = []
        var right: [(title: String, items: [Shortcut])] = []
        var leftRows = 0
        var rightRows = 0
        for group in groups {
            // A group costs its rows plus its heading.
            if leftRows <= rightRows {
                left.append(group)
                leftRows += group.items.count + 1
            } else {
                right.append(group)
                rightRows += group.items.count + 1
            }
        }
        return (left, right)
    }

    /// The sheet's search: a case-insensitive match on the title, the group, or the glyphs.
    static func filter(_ query: String) -> [(title: String, items: [Shortcut])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sheetGroups }
        return sheetGroups.compactMap { group in
            let hits = group.items.filter {
                $0.title.lowercased().contains(q) || group.title.lowercased().contains(q)
                    || $0.glyphs.lowercased().contains(q)
            }
            return hits.isEmpty ? nil : (group.title, hits)
        }
    }
}
