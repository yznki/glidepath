import SwiftUI

enum RadarMode: Equatable {
    case running, idle, paused
}

/// One PR on the radar. `progress` is the target distance from the centre, as a fraction of the outer ring.
struct Blip: Equatable {
    let id: String
    let progress: Double
    let verdict: Verdict?
    let active: Bool
}

/// The radar as an instrument (docs/design.md): two rings and a crosshair, a sweep arm only while running,
/// one blip per PR, a breathing idle state, an afterglow as the arm passes, and a ping when a PR lands.
/// No gradients. Reduced motion freezes the arm, the breathing and the pings.
struct RadarView: View {
    let blips: [Blip]
    let mode: RadarMode
    let hovered: String?
    let motion: RadarMotion
    var onHover: (String?) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = Metrics.radar
    private static let period = 3.0
    private static let afterglowWindow = 0.2   // 600 ms of a 3 s revolution

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : nil)) { context in
            Canvas { gc, size in
                draw(&gc, size, now: context.date)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): onHover(nearest(to: point))
            case .ended: onHover(nil)
            }
        }
    }

    private var outer: Double { Double(Self.size) / 2 - 3 }
    private var centre: CGPoint { CGPoint(x: Self.size / 2, y: Self.size / 2) }

    static func slot(_ index: Int, of count: Int) -> Double {
        -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(max(count, 1))
    }

    private func point(_ r: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
    }

    private func blipPoint(_ index: Int, _ blip: Blip) -> CGPoint {
        let r = (motion.radius[blip.id] ?? blip.progress) * outer
        return point(r, Self.slot(index, of: blips.count))
    }

    private func nearest(to p: CGPoint) -> String? {
        var best: (String, Double)?
        for (i, blip) in blips.enumerated() {
            let q = blipPoint(i, blip)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < 9, best == nil || d < best!.1 { best = (blip.id, d) }
        }
        return best?.0
    }

    private func colour(_ blip: Blip, _ p: Palette) -> Color {
        if let v = blip.verdict { return p.verdictFill(v) }
        return blip.active ? p.doing : p.secondary
    }

    private func draw(_ gc: inout GraphicsContext, _ size: CGSize, now: Date) {
        let p = Palette(scheme)
        let t = now.timeIntervalSinceReferenceDate
        let c = centre
        let reduce = reduceMotion
        motion.advance(targets: Dictionary(uniqueKeysWithValues: blips.map { ($0.id, $0.progress) }),
                       now: now, reduceMotion: reduce)

        // Rings and crosshair.
        for fraction in [0.5, 1.0] {
            let r = outer * fraction
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                      with: .color(p.ink.opacity(0.18)), lineWidth: 1)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - outer, y: c.y))
        cross.addLine(to: CGPoint(x: c.x + outer, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - outer))
        cross.addLine(to: CGPoint(x: c.x, y: c.y + outer))
        gc.stroke(cross, with: .color(p.ink.opacity(0.18)), lineWidth: 1)

        // Sweep arm: running only. Paused freezes it at -45 degrees, faded.
        var arm: Double? = nil
        switch mode {
        case .running:
            arm = reduce ? -Double.pi / 4 : -Double.pi / 2 + (t.truncatingRemainder(dividingBy: Self.period) / Self.period) * 2 * Double.pi
        case .paused:
            arm = -Double.pi / 4
        case .idle:
            arm = nil
        }
        if let arm {
            var line = Path()
            line.move(to: c)
            line.addLine(to: point(outer, arm))
            gc.stroke(line, with: .color(p.doing.opacity(mode == .paused ? 0.3 : 1)), lineWidth: 1.5)
        }

        // Blips.
        for (i, blip) in blips.enumerated() {
            var base: Double
            switch mode {
            case .idle:
                base = reduce ? 1 : 0.85 + 0.15 * sin(2 * Double.pi * t / 4)  // breathing, 4 s
            case .paused:
                base = 0.5
            case .running:
                base = 0.6
                if let arm, !reduce {
                    let slot = Self.slot(i, of: blips.count)
                    var since = (arm - slot).truncatingRemainder(dividingBy: 2 * Double.pi)
                    if since < 0 { since += 2 * Double.pi }
                    let fraction = since / (2 * Double.pi)
                    if fraction < Self.afterglowWindow {
                        base = 0.6 + 0.4 * (1 - fraction / Self.afterglowWindow)  // brightens as the arm passes
                    }
                }
            }
            let q = blipPoint(i, blip)
            let dot = Path(ellipseIn: CGRect(x: q.x - 3.5, y: q.y - 3.5, width: 7, height: 7))
            gc.fill(dot, with: .color(colour(blip, p).opacity(base)))
            if hovered == blip.id {
                let ring = Path(ellipseIn: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12))
                gc.stroke(ring, with: .color(p.ink), lineWidth: 1)
            }
            if !reduce, let start = motion.pingStart[blip.id] {
                let elapsed = now.timeIntervalSince(start)
                if elapsed >= 0 && elapsed < 0.5 {
                    let k = elapsed / 0.5
                    let r = 3.5 * (1 + 1.2 * k)
                    let ping = Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
                    gc.stroke(ping, with: .color(colour(blip, p).opacity(0.6 * (1 - k))), lineWidth: 1)
                }
            }
        }
    }
}
