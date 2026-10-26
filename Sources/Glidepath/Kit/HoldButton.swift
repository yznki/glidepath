import SwiftUI

/// The timing of a hold, apart from the view so it is tested. A press fills over `duration` and fires once; letting go
/// early drains it. A quick tap shows the hint ("Hold to post") with a small shake instead.
@MainActor
final class HoldModel: ObservableObject {
    static let duration: TimeInterval = 0.6
    /// Shorter than this is a tap: show the hint.
    static let tapLimit: TimeInterval = 0.3
    static let hintShown: TimeInterval = 1.8

    enum Release: Equatable { case tap, cancel, done }

    /// 0 to 1: how far the light has filled. Changed inside `withAnimation`, so views just read it.
    @Published private(set) var fill: CGFloat = 0
    @Published private(set) var showHint = false
    /// Bumped on every tap; drives the shake.
    @Published private(set) var shakes: CGFloat = 0

    private var pressedAt: Date?
    private var fired = false
    private var action: (() -> Void)?
    private var timer: Task<Void, Never>?
    private var hintTimer: Task<Void, Never>?

    /// What letting go after `held` seconds means.
    nonisolated static func release(after held: TimeInterval) -> Release {
        held >= duration ? .done : held < tapLimit ? .tap : .cancel
    }

    var isPressed: Bool { pressedAt != nil }

    func press(at now: Date = Date(), action: @escaping () -> Void) {
        guard pressedAt == nil else { return }
        pressedAt = now
        fired = false
        self.action = action
        withAnimation(.linear(duration: Self.duration)) { fill = 1 }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
            if !Task.isCancelled { self?.fire() }
        }
    }

    /// The hold reached full: perform once.
    func fire() {
        guard pressedAt != nil, !fired else { return }
        fired = true
        action?()
    }

    @discardableResult
    func release(at now: Date = Date()) -> Release {
        guard let at = pressedAt else { return .cancel }
        timer?.cancel()
        let outcome: Release = fired ? .done : Self.release(after: now.timeIntervalSince(at))
        if outcome == .done { fire() }   // held long enough, but let go before the timer ran
        pressedAt = nil
        action = nil
        withAnimation(.easeOut(duration: outcome == .done ? 0.4 : 0.3)) { fill = 0 }
        if outcome == .tap { tapped() }
        return outcome
    }

    private func tapped() {
        withAnimation(.snappy) { showHint = true }
        withAnimation(.linear(duration: 0.3)) { shakes += 1 }
        hintTimer?.cancel()
        hintTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.hintShown * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { self?.showHint = false }
        }
    }
}

/// The one button for everything that goes to GitHub as you (spec §5.2): Post review, Push fix, Send reply, Merge,
/// Open revert PR, turning on Autopilot. The label names the action; holding 0.6 s fills its glass with light and
/// performs it. A tap shows the hint with a small shake. Keyboard: hold Space or ⌘Return while focused, or drive it
/// with `held` (hold Space on the selected row). VoiceOver performs it directly. Anything else is a plain button.
struct HoldButton: View {
    let title: String
    let hint: String
    var held: Bool
    let action: () -> Void
    private let shared: HoldModel?

    @StateObject private var own = HoldModel()

    /// The button fills itself.
    init(_ title: String, hint: String, held: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.held = held
        self.action = action
        shared = nil
    }

    /// The light fills the parent's glass pane instead: the parent draws `LightFill(progress: model.fill)`.
    init(_ title: String, hint: String, model: HoldModel, held: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.held = held
        self.action = action
        shared = model
    }

    var body: some View {
        HoldFace(title: title, hint: hint, held: held, fillsParent: shared != nil, model: shared ?? own, action: action)
    }
}

private struct HoldFace: View {
    let title: String
    let hint: String
    let held: Bool
    let fillsParent: Bool
    @ObservedObject var model: HoldModel
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            if model.showHint {
                Text(hint)
                    .font(Ladder.secondary)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            label
                .modifier(Shake(animatableData: model.shakes))
                .onLongPressGesture(minimumDuration: HoldModel.duration, maximumDistance: 24, perform: {}) { down in
                    if down { press() } else { model.release() }
                }
                .focusable()
                .onKeyPress(keys: [.space, .return], phases: [.down, .up]) { key in
                    guard key.key == .space || key.modifiers.contains(.command) else { return .ignored }
                    if key.phase == .down { press() } else { model.release() }
                    return .handled
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityHint(hint)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if isEnabled { action() } }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .onChange(of: held, initial: true) { _, down in if down { press() } else { model.release() } }
    }

    private func press() {
        guard isEnabled else { return }
        model.press(action: action)
    }

    @ViewBuilder private var label: some View {
        let text = Text(title)
            .font(Ladder.action)
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
        if fillsParent {
            // Inside a glass pane: no glass on glass, a quiet capsule.
            text.background(.white.opacity(0.1), in: Capsule()).contentShape(Capsule())
        } else {
            text
                .background(LightFill(progress: model.fill))
                .clipShape(Capsule())
                .glassCapsule(interactive: true)
                .contentShape(Capsule())
        }
    }
}

/// Light pouring left to right along the line's direction, brightest at its soft leading edge.
struct LightFill: View {
    var progress: CGFloat

    var body: some View {
        GeometryReader { g in
            let w = g.size.width * progress
            LinearGradient(stops: [.init(color: .white.opacity(0.06), location: 0),
                                   .init(color: .white.opacity(0.26), location: 0.7),
                                   .init(color: .white.opacity(0.55), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: w)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: max(0, 1 - 40 / max(w, 1))),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .opacity(progress > 0.001 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

/// A small side-to-side shake, once per whole step of `animatableData`.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(animatableData * .pi * 4), y: 0))
    }
}
