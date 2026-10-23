import SwiftUI

/// Cursor position and hover state for one glass card's specular highlight.
final class SpotModel: ObservableObject {
    @Published var pointer = CGPoint.zero
    @Published var hovering = false
}

/// The light a glass card shows: its colour, and whether it breathes (held reviews).
enum VerdictLight {
    case approve, changes, skipped, running, none
}

extension View {
    /// Glass card surface. `glassBlur` scales the blur: at 0 the tint is opaque. Adds a verdict light,
    /// a hairline edge and a specular highlight that follows the pointer.
    /// `piled` raises the tint, so a card under an open card does not show the text behind it.
    func glassCard(radius: CGFloat = 20, verdict: VerdictLight = .none, held: Bool = false,
                   piled: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, verdict: verdict, held: held, piled: piled))
    }
}

private struct GlassCard: ViewModifier {
    let radius: CGFloat
    let verdict: VerdictLight
    let held: Bool
    var piled = false

    @AppStorage("glassBlur") private var blur = 22.0
    @AppStorage("signalColour") private var signalKey = "amber"
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var spot = SpotModel()

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .contentShape(shape)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    spot.pointer = point
                    spot.hovering = true
                case .ended:
                    spot.hovering = false
                }
            }
            .background { surface(shape) }
    }

    private func surface(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial).opacity(blurFraction)
            shape.fill(Color(hex: "141419").opacity(tintOpacity))
            shape.fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                      startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.38)))
            light
            GeometryReader { geo in
                RadialGradient(colors: [.white.opacity(0.22), .clear],
                               center: UnitPoint(x: spot.pointer.x / max(geo.size.width, 1),
                                                 y: spot.pointer.y / max(geo.size.height, 1)),
                               startRadius: 0, endRadius: 260)
                    .opacity(spot.hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: spot.hovering)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [Gotham.hi, .clear, .clear, .white.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
    }

    /// The blur as 0...1: 0 has no material, 1 (blur 40) has the full material.
    private var blurFraction: Double { min(max(blur, 0), 40) / 40 }

    /// Opaque at blur 0, 0.66 (the prototype tint) at blur 40.
    private var tintOpacity: Double { piled ? max(1 - 0.34 * blurFraction, 0.94) : 1 - 0.34 * blurFraction }

    private var light: some View {
        let colour: Color
        let base: Double
        switch verdict {
        case .approve: colour = Gotham.approve; base = 0.12
        case .changes: colour = Gotham.signal(signalKey); base = 0.26
        case .running: colour = Gotham.run; base = 0.12
        case .skipped, .none: colour = Gotham.skipped; base = 0
        }
        return VerdictGlow(colour: colour, base: base, held: held)
    }
}

/// Whether a held card's light is at its peak.
final class BreathModel: ObservableObject {
    @Published var breathing = false
}

/// The blurred light in the card's top-right corner. Held cards breathe on a 3.2 s cycle, unless motion is reduced.
private struct VerdictGlow: View {
    let colour: Color
    let base: Double
    let held: Bool

    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = BreathModel()

    var body: some View {
        // An overlay on a flexible view: the 150 x 110 light is taller than a closed card, and as a layout child it
        // would make the whole surface that tall. Here it only paints, and the surface's clip keeps it inside.
        Color.clear
            .overlay(alignment: .topTrailing) {
                Ellipse()
                    .fill(colour)
                    .frame(width: 150, height: 110)
                    .blur(radius: 44)
                    .opacity(held ? (model.breathing ? 0.42 : 0.08) : base)
                    .scaleEffect(held ? (model.breathing ? 1.1 : 0.85) : 1)
                    .offset(x: 50, y: -50)
            }
            .onAppear(perform: breathe)
            .onChange(of: held) { _, _ in breathe() }
    }

    private func breathe() {
        guard held, !Motion.reduced(reduceMotion) else {
            model.breathing = false
            return
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            model.breathing = true
        }
    }
}
