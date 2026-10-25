import SwiftUI
import AppKit

/// The approach chart's layout, in the prototype's 1000 x 330 space. Pure, so the placement is tested without drawing.
enum ApproachGeometry {
    static let width: CGFloat = 1000
    static let height: CGFloat = 330
    static let fanStart: CGFloat = 40
    /// The runway's left edge and its centre line.
    static let runwayX: CGFloat = 880
    static let runwayY: CGFloat = 165
    /// The x of each marker: outer (CI), middle (review), inner (ready). A plane at marker 0 has not passed the outer one.
    static let markerX: [CGFloat] = [130, 300, 520, 720]
    static let taxiX: CGFloat = 120
    /// How far a stack's follower trails the one ahead of it.
    static let trail: CGFloat = 90
    static let laneCount = 5

    /// The x of a plane: the furthest marker it has passed. Taxiing planes stand before the outer marker.
    static func planeX(marker: Int, phase: ApproachPhase) -> CGFloat {
        switch phase {
        case .taxiing: return taxiX
        case .landed: return runwayX
        default: return markerX[min(max(marker, 0), markerX.count - 1)]
        }
    }

    /// The y of a lane at x. Lane n starts at 60 + 55n and eases toward the runway's centre line as x nears it.
    static func laneY(lane: Int, x: CGFloat) -> CGFloat {
        let base = 60 + 55 * CGFloat(min(max(lane, 0), laneCount - 1))
        let t = min(max((x - fanStart) / (runwayX - fanStart), 0), 1)
        return base + (runwayY - base) * t
    }

    /// Where each plane's glyph sits, keyed by `ApproachPlane.id`. A stack's leader (stack index 1) sits at its marker;
    /// each follower trails the plane ahead of it by `trail`.
    static func positions(_ planes: [ApproachPlane]) -> [String: CGPoint] {
        var leaderX: [Int: CGFloat] = [:]
        for plane in planes where plane.stackIndex == 1 {
            leaderX[plane.lane] = planeX(marker: plane.marker, phase: plane.phase)
        }
        var out: [String: CGPoint] = [:]
        for plane in planes {
            var x = planeX(marker: plane.marker, phase: plane.phase)
            if let k = plane.stackIndex, k > 1, let lead = leaderX[plane.lane] {
                x = max(60, lead - trail * CGFloat(k - 1))
            }
            out[plane.id] = CGPoint(x: x, y: laneY(lane: plane.lane, x: x))
        }
        return out
    }

    /// The heading of a glyph: along the glide slope toward the runway, in radians.
    static func heading(_ p: CGPoint) -> CGFloat {
        atan2(runwayY - p.y, runwayX - p.x)
    }
}

extension ApproachPlane: Identifiable {
    var id: String { "\(slug)#\(n)" }
}

/// Maps the 1000 x 330 model space to a canvas. The full chart keeps the model's aspect ratio. The compact chart (the
/// popover's) squeezes the same layout into its frame, with no labels.
struct ApproachFrame {
    let size: CGSize
    let compact: Bool

    var sx: CGFloat { compact ? (size.width - 16) / (ApproachGeometry.runwayX + 104 - ApproachGeometry.fanStart) : size.width / ApproachGeometry.width }
    var sy: CGFloat { compact ? size.height / ApproachGeometry.height : size.width / ApproachGeometry.width }

    func point(_ p: CGPoint) -> CGPoint {
        if compact {
            return CGPoint(x: 8 + (p.x - ApproachGeometry.fanStart) * sx,
                           y: size.height / 2 + (p.y - ApproachGeometry.runwayY) * sy)
        }
        return CGPoint(x: p.x * sx, y: p.y * sy)
    }

    /// A model length along x, in canvas points.
    func dx(_ v: CGFloat) -> CGFloat { v * sx }
    /// A model length along y, in canvas points.
    func dy(_ v: CGFloat) -> CGFloat { v * sy }
    /// The glyph's scale: the jet is about 18 model units long.
    var glyph: CGFloat { compact ? 0.62 : sx }
}

/// The approach chart: each open PR as a glyph on the glide slope, the markers and the runway. Drawn with `Canvas`
/// on a `TimelineView` clock, so the phases animate. Reduce Motion and snapshots draw one still frame.
struct ApproachChart: View {
    let planes: [ApproachPlane]
    var compact = false
    /// Called with the plane's id when a glyph is tapped (full chart only).
    var onTap: (String) -> Void = { _ in }

    @Environment(\.offscreenRender) private var offscreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("motion") private var motion = "full"
    @AppStorage("signalColour") private var signalKey = "amber"

    var body: some View {
        let still = offscreen || Motion.reduced(reduceMotion)
        let aspect = compact ? 360.0 / 84.0 : ApproachGeometry.width / ApproachGeometry.height
        SnapshotTimeline(schedule: .animation(minimumInterval: 1.0 / 30, paused: still)) { date in
            Canvas { ctx, size in
                let painter = ApproachPainter(planes: planes, frame: ApproachFrame(size: size, compact: compact),
                                              signal: Gotham.signal(signalKey), still: still)
                painter.paint(&ctx, t: still ? 0 : date.timeIntervalSinceReferenceDate)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .overlay {
            if !offscreen && !compact {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            if let id = nearest(to: value.location, size: geo.size) { onTap(id) }
                        })
                }
            }
        }
    }

    /// The plane whose glyph is nearest the tap, within 22 points.
    private func nearest(to point: CGPoint, size: CGSize) -> String? {
        let frame = ApproachFrame(size: size, compact: false)
        let positions = ApproachGeometry.positions(planes)
        var best: (id: String, d: CGFloat)?
        for plane in planes {
            guard let p = positions[plane.id] else { continue }
            let c = frame.point(p)
            let d = hypot(c.x - point.x, c.y - point.y)
            if d <= 22, best == nil || d < best!.d { best = (plane.id, d) }
        }
        return best?.id
    }
}

/// The drawing of one frame. `still` drops the sweep, rings and trails, and holds a holding glyph at its marker.
struct ApproachPainter {
    let planes: [ApproachPlane]
    let frame: ApproachFrame
    let signal: Color
    let still: Bool

    private static let ink = Color.white
    private static let mute = Gotham.mute
    private static let faint = Color.white.opacity(0.22)

    func paint(_ ctx: inout GraphicsContext, t: Double) {
        fan(&ctx)
        markers(&ctx)
        runway(&ctx, t: t)
        let positions = ApproachGeometry.positions(planes)
        let order: [ApproachPhase] = [.taxiing, .waiting, .cleared, .flying, .holding]
        for phase in order {
            for plane in planes where plane.phase == phase {
                guard let p = positions[plane.id] else { continue }
                glyph(&ctx, plane, at: p, t: t)
            }
        }
        if !still { sweep(&ctx, t: t) }
    }

    // MARK: Chart furniture

    private func fan(_ ctx: inout GraphicsContext) {
        let end = frame.point(CGPoint(x: ApproachGeometry.runwayX, y: ApproachGeometry.runwayY))
        for y in [40, 100, 165, 230, 290] as [CGFloat] {
            var path = Path()
            path.move(to: frame.point(CGPoint(x: ApproachGeometry.fanStart, y: y)))
            path.addLine(to: end)
            ctx.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
    }

    private func markers(_ ctx: inout GraphicsContext) {
        let curves: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 300, y: 20), CGPoint(x: 330, y: 165), CGPoint(x: 300, y: 310)),
            (CGPoint(x: 520, y: 45), CGPoint(x: 545, y: 165), CGPoint(x: 520, y: 285)),
            (CGPoint(x: 720, y: 80), CGPoint(x: 738, y: 165), CGPoint(x: 720, y: 250)),
        ]
        for (start, control, end) in curves {
            var path = Path()
            path.move(to: frame.point(start))
            path.addQuadCurve(to: frame.point(end), control: frame.point(control))
            ctx.stroke(path, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
        }
        guard !frame.compact else { return }
        label(&ctx, "OUTER · CI", at: frame.point(CGPoint(x: 288, y: 16)), size: 10, mono: true, color: Self.faint)
        label(&ctx, "MIDDLE · REVIEW", at: frame.point(CGPoint(x: 488, y: 40)), size: 10, mono: true, color: Self.faint)
        label(&ctx, "INNER · READY", at: frame.point(CGPoint(x: 690, y: 74)), size: 10, mono: true, color: Self.faint)
    }

    private func runway(_ ctx: inout GraphicsContext, t: Double) {
        let rect = CGRect(origin: frame.point(CGPoint(x: 880, y: 150)),
                          size: CGSize(width: frame.dx(104), height: frame.dy(30)))
        let gradient = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white.opacity(0.02), .white.opacity(0.12)]),
            startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: gradient)
        ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.white.opacity(0.18)), lineWidth: 1)
        var centre = Path()
        centre.move(to: frame.point(CGPoint(x: 892, y: 165)))
        centre.addLine(to: frame.point(CGPoint(x: 972, y: 165)))
        ctx.stroke(centre, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
        // The approach lights blink in turn, as the prototype's do; still, they show at a steady level.
        for (i, y) in [150, 158, 172, 180].enumerated() {
            let phase = still ? 0.6 : 0.25 + 0.75 * max(0, sin(t * 2 * .pi / 1.6 - Double(i) * 0.4))
            let c = frame.point(CGPoint(x: 874, y: CGFloat(y)))
            let r: CGFloat = 1.6 * frame.glyph * 1.4
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(.white.opacity(phase)))
        }
        guard !frame.compact else { return }
        label(&ctx, "MAIN", at: frame.point(CGPoint(x: 902, y: 200)), size: 10, mono: true, color: Self.faint)
    }

    /// The radar sweep: a soft band that crosses the chart every 7 s.
    private func sweep(_ ctx: inout GraphicsContext, t: Double) {
        let w = frame.size.width
        let frac = CGFloat((t.truncatingRemainder(dividingBy: 7)) / 7)
        let band = w * 0.2
        let x0 = -band + frac * (w + band)
        let rect = CGRect(x: x0, y: 0, width: band, height: frame.size.height)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.035), location: 0.5),
                             .init(color: .clear, location: 1)]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0))
        ctx.fill(Path(rect), with: shading)
    }

    // MARK: Planes

    private func glyph(_ ctx: inout GraphicsContext, _ plane: ApproachPlane, at p: CGPoint, t: Double) {
        var at = p
        var angle = ApproachGeometry.heading(p)
        var colour = Self.ink
        var alpha: Double = 1
        let follower = (plane.stackIndex ?? 1) > 1

        switch plane.phase {
        case .taxiing:
            alpha = 0.35
        case .waiting:
            alpha = 0.8
        case .holding:
            // Circles a racetrack loop, 34 by 12 units, every 5 s. Still, it holds at the top of the loop, facing right.
            colour = signal
            let loopCentre = frame.point(p)
            let theta = still ? -Double.pi / 2 : 2 * Double.pi * t / 5
            let ellipse = CGRect(x: loopCentre.x - frame.dx(34), y: loopCentre.y - frame.dy(12),
                                 width: frame.dx(68), height: frame.dy(24))
            ctx.stroke(Path(ellipseIn: ellipse), with: .color(signal.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            // In model units: `c` below maps it to the canvas once.
            at = CGPoint(x: p.x + 34 * CGFloat(cos(theta)), y: p.y + 12 * CGFloat(sin(theta)))
            // The tangent of the loop, so the glyph faces along it.
            angle = atan2(12 * CGFloat(cos(theta)) * frame.sy, -34 * CGFloat(sin(theta)) * frame.sx)
        case .flying:
            if !still {
                let phase = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
                let r = 9 + 13 * CGFloat(phase)
                let c = frame.point(p)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.7 * (1 - phase))), lineWidth: 1)
                // A dashed trail 170 units behind, moving forward.
                var trail = Path()
                trail.move(to: frame.point(CGPoint(x: p.x - 170, y: p.y)))
                trail.addLine(to: frame.point(CGPoint(x: p.x - 10, y: p.y)))
                ctx.stroke(trail, with: .color(.white.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4], dashPhase: CGFloat(-t * 14)))
            }
        case .cleared:
            colour = Self.ink
        case .landed, .taxiing:
            break
        }
        if follower { alpha *= 0.7 }
        let c = frame.point(at)
        // The jet points along its heading: the prototype's glyph, scaled to the chart.
        ctx.fill(jet(at: c, angle: angle, scale: frame.glyph), with: .color(colour.opacity(alpha)))

        guard !frame.compact else { return }
        let stack = plane.stackIndex
        let headline = stack.map { $0 > 1 ? "#\(plane.n) · \($0)" : "#\(plane.n)" } ?? "#\(plane.n)"
        label(&ctx, headline, at: CGPoint(x: c.x + 12, y: c.y - 9), size: 12, weight: .semibold,
              color: Color(hex: "ECECEF"))
        if !follower {
            let amber = plane.phase == .holding || plane.phase == .cleared
            let statusColour: Color = amber ? signal : (plane.phase == .flying ? Gotham.fg.opacity(0.8) : Self.mute)
            label(&ctx, fitted(plane.label, width: frame.dx(240)), at: CGPoint(x: c.x + 12, y: c.y + 8), size: 11,
                  color: statusColour)
        }
    }

    /// The jet glyph's outline: nose at +x, tail at -x, centred on `c`.
    private func jet(at c: CGPoint, angle: CGFloat, scale: CGFloat) -> Path {
        let points: [(CGFloat, CGFloat)] = [(10, 0), (-8, -6), (-4, 0), (-8, 6)]
        let cs = cos(angle), sn = sin(angle)
        var path = Path()
        for (i, p) in points.enumerated() {
            let q = CGPoint(x: c.x + (p.0 * cs - p.1 * sn) * scale, y: c.y + (p.0 * sn + p.1 * cs) * scale)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }

    /// The text cut to `width` points at 11 point, ending in an ellipsis when it is cut. Status labels are capped at
    /// 240 units so one plane's status never runs into the next plane's.
    private func fitted(_ text: String, width: CGFloat) -> String {
        let font = NSFont.systemFont(ofSize: 11)
        func fits(_ s: String) -> Bool { (s as NSString).size(withAttributes: [.font: font]).width <= width }
        if fits(text) { return text }
        var cut = text
        while !cut.isEmpty && !fits(cut + "…") { cut.removeLast() }
        return cut + "…"
    }

    private func label(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat,
                       weight: Font.Weight = .regular, mono: Bool = false, color: Color) {
        let font: Font = mono ? .system(size: size, weight: weight, design: .monospaced) : .system(size: size, weight: weight)
        ctx.draw(Text(text).font(font).foregroundColor(color), at: p, anchor: .topLeading)
    }
}
