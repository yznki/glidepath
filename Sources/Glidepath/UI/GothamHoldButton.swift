import SwiftUI

/// State for a `GothamHoldButton`: fill level, whether a press is down, and whether it has fired.
final class GothamHoldModel: ObservableObject {
    @Published var level = 0.0
    @Published var pressing = false
    @Published var fired = false
}

/// Press-and-hold button. The fill grows over `duration` while held, drains 3x faster on release, and
/// fires `action` once at full. It then stays filled showing `doneTitle`; give it a new identity to reset.
struct GothamHoldButton: View {
    let title: String
    let doneTitle: String
    let tint: Color
    var duration: Double = 0.9
    /// The small form for rows: 28 points tall, 12 point type, sized to its title.
    var compact = false
    let action: () -> Void

    @StateObject private var model = GothamHoldModel()

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Gotham.row)
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0.15), tint], startPoint: .leading, endPoint: .trailing))
                .scaleEffect(x: model.fired ? 1 : model.level, anchor: .leading)
            Text(model.fired ? doneTitle : title)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundStyle(model.fired ? Color(hex: "050506") : Gotham.fg)
                .padding(.horizontal, compact ? 14 : 0)
                .frame(maxWidth: compact ? nil : .infinity)
        }
        .frame(height: compact ? 28 : 44)
        .fixedSize(horizontal: compact, vertical: false)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !model.pressing { model.pressing = true } }
            .onEnded { _ in model.pressing = false })
        .focusable(true) { focused in
            // Losing focus mid-press ends the press: the fill drains like a release.
            if !focused { model.pressing = false }
        }
        .onKeyPress(keys: [.space, .return], phases: .down) { _ in
            model.pressing = true
            return .handled
        }
        .onKeyPress(keys: [.space, .return], phases: .up) { _ in
            model.pressing = false
            return .handled
        }
        .accessibilityAddTraits(.isButton)
        .task(id: model.pressing) { await tick() }
        .onDisappear { model.pressing = false }
    }

    /// Runs once per press or release (the task restarts when `pressing` changes). Ends when it fires,
    /// or when released and drained.
    private func tick() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            let dt = now.timeIntervalSince(last)
            last = now
            model.level = min(1, max(0, model.level + (model.pressing ? dt : -3 * dt) / duration))
            if model.level >= 1 && !model.fired {
                model.fired = true
                action()
            }
            if model.fired || (!model.pressing && model.level == 0) { return }
        }
    }
}
