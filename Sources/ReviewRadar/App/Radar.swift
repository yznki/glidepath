import SwiftUI

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    static let scan = Color(hex: "#2BB3A3")
    static let approve = Color(hex: "#30A46C")
    static let changes = Color(hex: "#E5A000")
}

/// Stage 0...4 -> distance from center. Posted blips cluster near the center.
func blipRadius(stage: Int, posted: Bool, outer: Double) -> Double {
    if posted { return 0.12 * outer }
    return (1 - Double(min(max(stage, 0), 4)) / 4) * outer
}

struct RadarView: View {
    let strips: [Strip]
    let running: Bool
    var size: CGFloat = 84

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { gc, canvasSize in
                draw(&gc, canvasSize, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .opacity(running ? 1 : 0.4)
    }

    private func draw(_ gc: inout GraphicsContext, _ sz: CGSize, time: Double) {
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let outer = Double(min(sz.width, sz.height) / 2) - 3
        let line = Color.primary.opacity(0.08)
        let scan = Color.scan

        // Sweep angle in screen space (y down, so increasing angle is clockwise).
        let period = running ? 3.0 : 10.0
        let sweep = reduceMotion
            ? -Double.pi / 4
            : -Double.pi / 2 + (time.truncatingRemainder(dividingBy: period) / period) * 2 * Double.pi

        // Rings and crosshair.
        for k in 1...3 {
            let r = outer * Double(k) / 3
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            gc.stroke(ring, with: .color(line), lineWidth: 0.75)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - outer, y: c.y))
        cross.addLine(to: CGPoint(x: c.x + outer, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - outer))
        cross.addLine(to: CGPoint(x: c.x, y: c.y + outer))
        gc.stroke(cross, with: .color(line), lineWidth: 0.75)

        // Sweep wedge: 40 degrees trailing the leading edge, fading toward the trail.
        let wedgeSpan = 40 * Double.pi / 180
        let a0 = sweep - wedgeSpan
        var wedge = Path()
        wedge.move(to: c)
        for k in 0...24 {
            let a = a0 + wedgeSpan * Double(k) / 24
            wedge.addLine(to: point(c, outer, a))
        }
        wedge.closeSubpath()
        gc.fill(
            wedge,
            with: .conicGradient(
                Gradient(stops: [
                    .init(color: scan.opacity(0), location: 0),
                    .init(color: scan.opacity(0.55), location: CGFloat(40.0 / 360.0)),
                ]),
                center: c,
                angle: .radians(a0)
            )
        )

        var lead = Path()
        lead.move(to: c)
        lead.addLine(to: point(c, outer, sweep))
        gc.stroke(lead, with: .color(scan), lineWidth: 1)

        // Blips. Golden-angle spread; brightness decays behind the sweep over ~1.2 rad.
        let golden = 137.5 * Double.pi / 180
        for (i, strip) in strips.enumerated() {
            let phi = Double(i) * golden
            let r = blipRadius(stage: strip.stage, posted: strip.posted, outer: outer)
            let p = point(c, r, phi)
            var behind = (sweep - phi).truncatingRemainder(dividingBy: 2 * Double.pi)
            if behind < 0 { behind += 2 * Double.pi }
            let glow = behind < 1.2 ? 1 - behind / 1.2 : 0
            let alpha = 0.35 + 0.65 * glow

            let color: Color
            switch strip.verdict {
            case .approve?: color = .approve
            case .changes?: color = .changes
            case .skipped?: color = .secondary
            case nil: color = scan
            }
            let d: CGFloat = strip.posted ? 5 : 6
            let dot = Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
            gc.fill(dot, with: .color(color.opacity(alpha)))
        }

        // Center pivot.
        let pivot = Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3))
        gc.fill(pivot, with: .color(scan))
    }

    private func point(_ c: CGPoint, _ r: Double, _ a: Double) -> CGPoint {
        CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }
}
