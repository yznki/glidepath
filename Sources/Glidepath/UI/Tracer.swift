import SwiftUI

/// A silver arc that travels once round `shape` every `period` seconds, with a blurred copy for glow.
/// Under reduced motion the ring stays still.
struct Tracer<S: InsettableShape>: View {
    let shape: S
    var lineWidth: CGFloat = 1
    var period: Double = 2.6

    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = Motion.reduced(reduceMotion)
        TimelineView(.animation(paused: still)) { context in
            let turn = still ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            ZStack {
                shape.strokeBorder(sweep(turn), lineWidth: lineWidth * 4)
                    .blur(radius: 6)
                    .opacity(0.7)
                shape.strokeBorder(sweep(turn), lineWidth: lineWidth)
            }
        }
    }

    /// Clear for 62% of the turn, then a bright head that fades back to clear, as in the prototype conic.
    private func sweep(_ turn: Double) -> AngularGradient {
        let stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.62),
            .init(color: .white.opacity(0.95), location: 0.94),
            .init(color: .clear, location: 1),
        ]
        return AngularGradient(gradient: Gradient(stops: stops), center: .center,
                               startAngle: .degrees(turn * 360), endAngle: .degrees(turn * 360 + 360))
    }
}
