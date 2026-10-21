import SwiftUI

/// What a PR is doing, as the profile shows it.
enum MarkKind: Equatable {
    case active(stage: Int)   // 1...4 on the slope: a blue circle, labelled with its number
    case queued               // running, not started yet: a hollow grey circle at the top of the slope
    case landed(Verdict)      // on the runway: a circle (approved), triangle (changes) or dash (skipped)
    case dropped              // finished without a verdict: a hollow grey circle on the runway
}

struct ProfileMark: Equatable, Identifiable {
    let id: String
    let kind: MarkKind
    /// "#1113", shown above an in-flight dot.
    var label: String = ""
}

/// A mark with its position worked out. Pure, so the layout rules can be tested.
struct PlacedMark: Equatable {
    let id: String
    let kind: MarkKind
    let label: String
    /// Circles: the centre on the slope. Landed marks: the centre on the runway.
    let centre: CGPoint
    /// Landed marks: their size (9 pt, smaller only when more than five land).
    let side: CGFloat
    var isLanded: Bool {
        switch kind {
        case .landed, .dropped: return true
        default: return false
        }
    }
    var isActive: Bool {
        if case .active = kind { return true }
        return false
    }
}

/// Geometry of the approach profile, in points, origin top left. Documented in docs/design.md.
enum Profile {
    static let width: CGFloat = 328
    static let height: CGFloat = 64
    static let compactHeight: CGFloat = 32
    static let slopeStart = CGPoint(x: 0, y: 18)
    static let slopeEnd = CGPoint(x: 268, y: 50)
    static let runwayX: CGFloat = 268
    static let runwayLength: CGFloat = 60
    static let runwayHeight: CGFloat = 4
    /// The runway's top edge: full profile at y = 52, compact at y = 26.
    static func runwayY(compact: Bool) -> CGFloat { compact ? 26 : 52 }
    static let landedSide: CGFloat = 9
    static let inFlightDiameter: CGFloat = 10
    static let spread: CGFloat = 11
    static let landingDuration: Double = 0.7

    static func slopeY(_ x: CGFloat) -> CGFloat {
        slopeStart.y + x / slopeEnd.x * (slopeEnd.y - slopeStart.y)
    }

    /// Centre x of stage n (1...4) on the slope: the middle of its quarter.
    static func stageX(_ n: Int) -> CGFloat {
        (CGFloat(min(max(n, 1), 4)) - 0.5) / 4 * slopeEnd.x
    }

    /// Places every mark. Circles on one stage spread 11 pt apart along the slope. Landed marks sit on the
    /// runway in list order, packed left to right; past five they shrink so they still fit.
    static func place(_ marks: [ProfileMark], compact: Bool = false) -> [PlacedMark] {
        var out: [PlacedMark] = []
        var byStage: [Int: [ProfileMark]] = [:]
        for m in marks { if case .active(let s) = m.kind { byStage[s, default: []].append(m) } }
        let queued = marks.filter { $0.kind == .queued }
        let landed = marks.filter { m in
            switch m.kind {
            case .landed, .dropped: return true
            default: return false
            }
        }
        for (stage, group) in byStage {
            for (k, m) in group.enumerated() {
                let offset = CGFloat(k) - CGFloat(group.count - 1) / 2
                let x = min(max(stageX(stage) + offset * spread, 0), slopeEnd.x - 6)
                out.append(PlacedMark(id: m.id, kind: m.kind, label: m.label, centre: CGPoint(x: x, y: slopeY(x)), side: inFlightDiameter))
            }
        }
        for (k, m) in queued.enumerated() {
            let x = min(CGFloat(k) * spread + 4, slopeEnd.x - 6)
            out.append(PlacedMark(id: m.id, kind: m.kind, label: m.label, centre: CGPoint(x: x, y: slopeY(x)), side: landedSide))
        }
        let count = landed.count
        let step: CGFloat = count <= 1 ? 0 : min(11, (runwayLength - landedSide) / CGFloat(count - 1))
        let side: CGFloat = count <= 5 ? landedSide : max(min(landedSide, step - 1.5), 3)
        let top = runwayY(compact: compact)
        for (k, m) in landed.enumerated() {
            let left = runwayX + CGFloat(k) * step
            out.append(PlacedMark(id: m.id, kind: m.kind, label: m.label,
                                  centre: CGPoint(x: left + side / 2, y: top - side / 2), side: side))
        }
        return out
    }

    /// Radius of a placed mark, for the hover ring.
    static func radius(_ pm: PlacedMark) -> CGFloat {
        pm.isActive ? inFlightDiameter / 2 : pm.side / 2
    }
}

/// Per-frame motion for the profile: circles drift along the slope, landings slide onto the runway. Not SwiftUI
/// state, so animating it does not re-render the view tree.
final class ProfileMotion {
    private(set) var lastCircle: [String: CGPoint] = [:]
    private var landings: [String: (from: CGPoint, start: Date)] = [:]

    /// `justLanded` comes from the store: PRs that got a verdict while the popover was open.
    func advance(_ placed: [PlacedMark], justLanded: Set<String>, now: Date, reduce: Bool) {
        for pm in placed where pm.isActive {
            lastCircle[pm.id] = pm.centre
        }
        guard !reduce else { return }
        for id in justLanded where landings[id] == nil {
            if let from = lastCircle[id] { landings[id] = (from, now) }
        }
    }

    /// Where a landing circle is at `now`, and its progress (0 to 1), or nil when no landing is running.
    func landing(_ id: String, target: CGPoint, now: Date) -> (point: CGPoint, progress: Double)? {
        guard let l = landings[id] else { return nil }
        let elapsed = now.timeIntervalSince(l.start)
        guard elapsed >= 0, elapsed < Profile.landingDuration else { return nil }
        let u = elapsed / Profile.landingDuration
        let eased = 1 - pow(1 - u, 3)
        let x = l.from.x + (target.x - l.from.x) * CGFloat(eased)
        let y = l.from.y + (target.y - l.from.y) * CGFloat(eased)
        return (CGPoint(x: x, y: y), u)
    }
}

enum ProfileMode: Equatable {
    case running, idle, paused, failed
}

/// The approach profile (docs/design.md). Full (328 x 64) only while running. Idle, paused and failed with a
/// last run show the compact strip (32 pt): runway and landed marks, with a short lead-in of slope.
struct ApproachProfile: View {
    let marks: [ProfileMark]
    let mode: ProfileMode
    let compact: Bool
    let hovered: String?
    let justLanded: Set<String>
    let motion: ProfileMotion
    var onHover: (String?) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let drift: CGFloat = 6
    private static let driftLoop = 4.0

    var body: some View {
        let height = compact ? Profile.compactHeight : Profile.height
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : nil)) { context in
            Canvas { gc, _ in
                draw(&gc, now: context.date)
            }
        }
        .frame(width: Profile.width, height: height)
        .overlay(alignment: .topLeading) {
            if !compact { ticks }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): onHover(nearest(to: point))
            case .ended: onHover(nil)
            }
        }
    }

    /// Stage labels above the slope: 11/500 tertiary.
    private var ticks: some View {
        ZStack(alignment: .topLeading) {
            tick("gather", x: 0)
            tick("review", x: 88)
            tick("check", x: 176)
            tick("land", x: Profile.runwayX)
        }
        .frame(width: Profile.width, height: 12, alignment: .topLeading)
    }

    private func tick(_ label: String, x: CGFloat) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette(scheme).tertiary)
            .offset(x: x, y: 0)
    }

    private func nearest(to p: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for pm in Profile.place(marks, compact: compact) {
            let d = hypot(pm.centre.x - p.x, pm.centre.y - p.y)
            if d < 10, best == nil || d < best!.1 { best = (pm.id, d) }
        }
        return best?.0
    }

    private func draw(_ gc: inout GraphicsContext, now: Date) {
        let p = Palette(scheme)
        let t = now.timeIntervalSinceReferenceDate
        let placed = Profile.place(marks, compact: compact)
        let alpha: Double = mode == .paused ? 0.4 : 1
        motion.advance(placed, justLanded: justLanded, now: now, reduce: reduceMotion)
        let top = Profile.runwayY(compact: compact)

        // Slope: the full profile, or the short lead-in of the compact strip.
        var slope = Path()
        if compact {
            slope.move(to: CGPoint(x: 196, y: 6))
            slope.addLine(to: CGPoint(x: Profile.runwayX, y: 24))
        } else {
            slope.move(to: Profile.slopeStart)
            slope.addLine(to: Profile.slopeEnd)
        }
        gc.stroke(slope, with: .color(p.slope.opacity(alpha)), lineWidth: 2)

        // Runway, failed in the error colour with a 9 pt cross at its left end.
        let runway = CGRect(x: Profile.runwayX, y: top, width: Profile.runwayLength, height: Profile.runwayHeight)
        gc.fill(Path(runway), with: .color(mode == .failed ? p.error : p.runway.opacity(alpha)))
        if mode == .failed {
            var cross = Path()
            cross.move(to: CGPoint(x: 261.5, y: top - 9 + 2)); cross.addLine(to: CGPoint(x: 270.5, y: top - 9 + 11))
            cross.move(to: CGPoint(x: 270.5, y: top - 9 + 2)); cross.addLine(to: CGPoint(x: 261.5, y: top - 9 + 11))
            gc.stroke(cross, with: .color(p.error), lineWidth: 1.5)
        }
        // Paused: the pause glyph moves to the runway's right end.
        if mode == .paused {
            for x in [CGFloat(316), 322] {
                gc.fill(Path(CGRect(x: x, y: top - 10, width: 2, height: 8)), with: .color(p.secondary))
            }
        }

        // Marks, and the labels of in-flight dots that have room.
        var labelled: [CGFloat] = []
        for pm in placed.sorted(by: { $0.centre.x < $1.centre.x }) where pm.isActive {
            let shows = hovered == pm.id || labelled.allSatisfy { abs($0 - pm.centre.x) >= 36 }
            if shows { labelled.append(pm.centre.x) }
        }
        for pm in placed {
            let drift: CGFloat = (mode == .running && pm.isActive && !reduceMotion)
                ? Self.drift * CGFloat(1 - cos(2 * Double.pi * t / Self.driftLoop)) / 2 : 0
            let drawn = mark(pm, drift: drift, p: p, alpha: alpha)
            if let landing = motion.landing(pm.id, target: pm.centre, now: now) {
                let colour = landing.progress < 0.6 ? p.doingMark : verdictColour(pm.kind, p)
                gc.fill(Path(ellipseIn: CGRect(x: landing.point.x - 5, y: landing.point.y - 5, width: 10, height: 10)),
                        with: .color(colour))
            } else {
                draw(drawn, in: &gc)
            }
            if pm.isActive, hovered == pm.id || labelled.contains(pm.centre.x) {
                let text = Text(pm.label).font(.system(size: 11, weight: .medium)).foregroundStyle(p.tertiary)
                // Above the dot when the label clears the tick row (y 0 to 12); below it otherwise.
                let above = drawn.centre.y >= 33
                gc.draw(text, at: CGPoint(x: drawn.centre.x, y: above ? drawn.centre.y - 8 : drawn.centre.y + 8),
                        anchor: above ? .bottom : .top)
            }
            if hovered == pm.id {
                let r = Profile.radius(pm) + 5
                gc.stroke(Path(ellipseIn: CGRect(x: drawn.centre.x - r, y: drawn.centre.y - r, width: 2 * r, height: 2 * r)),
                          with: .color(ringColour(pm.kind, p)), lineWidth: 2)
            }
        }
    }

    private struct Drawn {
        let centre: CGPoint
        let side: CGFloat
        let colour: Color
        let kind: MarkKind
    }

    private func mark(_ pm: PlacedMark, drift: CGFloat, p: Palette, alpha: Double) -> Drawn {
        let slides = pm.isActive || pm.kind == .queued
        let x = min(pm.centre.x + drift, Profile.slopeEnd.x - 6)
        let centre = slides ? CGPoint(x: x, y: Profile.slopeY(x)) : pm.centre
        return Drawn(centre: centre, side: pm.side, colour: markColour(pm.kind, p).opacity(alpha), kind: pm.kind)
    }

    private func markColour(_ kind: MarkKind, _ p: Palette) -> Color {
        switch kind {
        case .active: return p.doingMark
        case .queued, .dropped: return p.skipMark
        case .landed(let verdict):
            switch verdict {
            case .changes: return p.changesMark
            case .approve: return p.approveMark
            case .skipped: return p.skipMark
            }
        }
    }

    private func ringColour(_ kind: MarkKind, _ p: Palette) -> Color {
        markColour(kind, p)
    }

    private func verdictColour(_ kind: MarkKind, _ p: Palette) -> Color {
        markColour(kind, p)
    }

    /// Shapes: in-flight and approved are circles, changes are triangles, skipped is a dash, queued and no result
    /// are hollow circles.
    private func draw(_ d: Drawn, in gc: inout GraphicsContext) {
        let c = d.centre
        switch shape(for: d) {
        case .disc(let diameter):
            gc.fill(Path(ellipseIn: CGRect(x: c.x - diameter / 2, y: c.y - diameter / 2, width: diameter, height: diameter)),
                    with: .color(d.colour))
        case .hollow(let diameter):
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - diameter / 2 + 0.75, y: c.y - diameter / 2 + 0.75,
                                             width: diameter - 1.5, height: diameter - 1.5)),
                      with: .color(d.colour), lineWidth: 1.5)
        case .triangle(let side):
            var tri = Path()
            tri.move(to: CGPoint(x: c.x, y: c.y - side / 2))
            tri.addLine(to: CGPoint(x: c.x + side / 2, y: c.y + side / 2))
            tri.addLine(to: CGPoint(x: c.x - side / 2, y: c.y + side / 2))
            tri.closeSubpath()
            gc.fill(tri, with: .color(d.colour))
        case .dash(let width):
            gc.fill(Path(roundedRect: CGRect(x: c.x - width / 2, y: c.y - 1.5, width: width, height: 3), cornerRadius: 1.5),
                    with: .color(d.colour))
        }
    }

    private enum Shape {
        case disc(CGFloat), hollow(CGFloat), triangle(CGFloat), dash(CGFloat)
    }

    private func shape(for d: Drawn) -> Shape {
        switch d.kind {
        case .active: return .disc(Profile.inFlightDiameter)
        case .queued, .dropped: return .hollow(d.side)
        case .landed(.approve): return .disc(d.side)
        case .landed(.changes): return .triangle(d.side)
        case .landed(.skipped): return .dash(d.side)
        }
    }
}
