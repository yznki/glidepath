import Foundation

/// A key a list responds to, before SwiftUI's key press is mapped to it.
enum ListKey: Equatable {
    case up, down, home, end, pageUp, pageDown
}

/// A move in a list. `groupPrevious` and `groupNext` jump between sweep groups (Reviews).
enum ListMove: Equatable {
    case up, down, first, last, pageUp, pageDown, groupPrevious, groupNext
}

/// List keyboard navigation as pure functions, so the rules are testable without a view. Indices are row indices in
/// the list as shown; `groupStarts` are the indices where a group (a sweep) begins, ascending.
enum ListNav {
    /// Rows per Page Up / Page Down.
    static let page = 8

    /// The move a key and its modifiers make. ⌘↑/⌘↓ and Home/End go to the ends; ⌥↑/⌥↓ jump between groups.
    static func move(_ key: ListKey, _ modifiers: ShortcutModifiers = []) -> ListMove? {
        switch key {
        case .up:
            if modifiers == [.command] { return .first }
            if modifiers == [.option] { return .groupPrevious }
            return modifiers.isEmpty ? .up : nil
        case .down:
            if modifiers == [.command] { return .last }
            if modifiers == [.option] { return .groupNext }
            return modifiers.isEmpty ? .down : nil
        case .home: return modifiers.isEmpty ? .first : nil
        case .end: return modifiers.isEmpty ? .last : nil
        case .pageUp: return modifiers.isEmpty ? .pageUp : nil
        case .pageDown: return modifiers.isEmpty ? .pageDown : nil
        }
    }

    /// The new selected index. Nil only when the list is empty. With no selection, every move lands on the first row.
    static func move(_ move: ListMove, from current: Int?, count: Int, groupStarts: [Int] = []) -> Int? {
        guard count > 0 else { return nil }
        let last = count - 1
        guard let current else { return 0 }
        let here = min(max(current, 0), last)
        switch move {
        case .up: return max(here - 1, 0)
        case .down: return min(here + 1, last)
        case .first: return 0
        case .last: return last
        case .pageUp: return max(here - page, 0)
        case .pageDown: return min(here + page, last)
        case .groupNext:
            return groupStarts.first { $0 > here } ?? here
        case .groupPrevious:
            // The start of this group when we are inside it, otherwise the start of the one before.
            if let own = groupStarts.last(where: { $0 <= here }), own < here { return own }
            return groupStarts.last { $0 < here } ?? here
        }
    }

    /// Type-to-select: the first title that starts with the typed text, searching after the current row. A
    /// repeated single letter cycles through the matches; longer text may match the current row itself.
    static func typeSelect(_ typed: String, titles: [String], from current: Int?) -> Int? {
        let query = typed.lowercased()
        guard !query.isEmpty, !titles.isEmpty else { return nil }
        let count = titles.count
        let cycling = query.count == 1
        let start = current.map { cycling ? $0 + 1 : $0 } ?? 0
        for offset in 0..<count {
            let index = ((start + offset) % count + count) % count
            if titles[index].lowercased().hasPrefix(query) { return index }
        }
        return nil
    }
}
