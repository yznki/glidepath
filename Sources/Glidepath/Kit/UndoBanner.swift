import SwiftUI

/// Discard and Remove are instant with Undo (spec §5.3): the banner shows for 8 seconds, ⌘Z works through the window's
/// UndoManager while it shows, and when it goes the change is final (`commit` runs). A new banner commits the last one.
@MainActor
final class UndoCenter: ObservableObject {
    static let shown: TimeInterval = 8

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var item: Item?

    private var undo: (() -> Void)?
    private var commit: (() -> Void)?
    private weak var manager: UndoManager?
    private var timer: Task<Void, Never>?

    func show(_ text: String, undoManager: UndoManager?, undo: @escaping () -> Void, commit: (() -> Void)? = nil) {
        finish()
        withAnimation(.glide) { item = Item(text: text) }
        self.undo = undo
        self.commit = commit
        manager = undoManager
        undoManager?.registerUndo(withTarget: self) { center in
            MainActor.assumeIsolated { center.undoNow() }
        }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.shown * 1_000_000_000))
            if !Task.isCancelled { self?.finish() }
        }
    }

    /// The Undo button and ⌘Z.
    func undoNow() {
        guard item != nil else { return }
        let undo = self.undo
        clear()
        undo?()
    }

    /// The banner's time is up: the change stays.
    func finish() {
        guard item != nil else { return }
        let commit = self.commit
        clear()
        commit?()
    }

    private func clear() {
        timer?.cancel()
        manager?.removeAllActions(withTarget: self)
        manager = nil
        undo = nil
        commit = nil
        withAnimation(.glide) { item = nil }
    }
}

/// The transient banner at the bottom of the window: what happened, and Undo.
struct UndoBanner: View {
    @ObservedObject var center: UndoCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let item = center.item {
                HStack(spacing: 14) {
                    Text(item.text).font(Ladder.body)
                    Button(Copy.undo) { center.undoNow() }
                        .glassButtonStyle()
                }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .glassCapsule()
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 18)
    }
}
