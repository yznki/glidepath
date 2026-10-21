import SwiftUI

/// What a PR is doing, as the profile shows it.
enum MarkKind: Equatable {
    case active(stage: Int)   // 1...4 on the slope, a circle
    case queued               // running, not started yet: a grey circle at the top of the slope
    case landed(Verdict)      // on the runway, a square in the verdict colour
    case dropped              // a finished run that never produced a verdict: a grey square
}

struct ProfileMark: Equatable, Identifiable {
    let id: String
    let kind: MarkKind
}

/// A mark with its position worked out. Pure, so the layout rules can be tested.
struct PlacedMark: Equatable {
    let id: String
    let kind: MarkKind
    let centre: CGPoint     // circles: the slope point; squares: the centre of the square on the runway
    let side: CGFloat       // 0 for circles (diameter 8)
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
    static let slopeStart = CGPoint(x: 0, y: 18)
    static let slopeEnd = CGPoint(x: 268, y: 50)
    static let runwayX: CGFloat = 268
    static let runwayY: CGFloat = 52
    static let runwayHeight: CGFloat = 4
    static let runwayLength: CGFloat = 60
    static let circleDiameter: CGFloat = 8
    static let spread: CGFloat = 10
    static let landingDuration: Double = 0.7

    static func slopeY(_ x: CGFloat) -> CGFloat {
        slopeStart.y + x / slopeEnd.x * (slopeEnd.y - slopeStart.y)
    }

    /// Centre x of stage n (1...4) on the slope: the middle of its quarter.
    static func stageX(_ n: Int) -> CGFloat {
        (CGFloat(min(max(n, 1), 4)) - 0.5) / 4 * slopeEnd.x
    }

    /// Places every mark. Circles on the same stage spread 10 pt apart along the slope; landed squares pack
    /// left to right on the runway in list order, shrinking when there are more than six.
    static func place(_ marks: [ProfileMark]) -> [PlacedMark] {
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
                out.append(PlacedMark(id: m.id, kind: m.kind, centre: CGPoint(x: x, y: slopeY(x)), side: 0))
            }
        }
        for (k, m) in queued.enumerated() {
            let x = min(CGFloat(k) * spread + 4, slopeEnd.x - 6)
            out.append(PlacedMark(id: m.id, kind: m.kind, centre: CGPoint(x: x, y: slopeY(x)), side: 0))
        }
        let count = landed.count
        let step: CGFloat = count <= 1 ? 0 : min(10, (runwayLength - 8) / CGFloat(count - 1))
        let side: CGFloat = count <= 6 ? 8 : max(step - 1.5, 2)
        for (k, m) in landed.enumerated() {
            let left = runwayX + CGFloat(k) * step
            out.append(PlacedMark(id: m.id, kind: m.kind,
                                  centre: CGPoint(x: left + side / 2, y: runwayY - side / 2), side: side))
        }
        return out
    }
}

/// Per-frame motion for the profile: circles drift, landings slide onto the runway. Not SwiftUI state, so
/// animating it does not re-render the view tree.
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

    /// Where a landing circle is at `now`, and its colour weight (0 = still in progress, 1 = landed), or nil.
    func landing(_ id: String, target: CGPoint, now: Date) -> (point: CGPoint, progress: Double)? {
        guard let l = landings[id] else { return nil }
        let elapsed = now.timeIntervalSince(l.start)
        guard elapsed >= 0, elapsed < Profile.landingDuration else { return nil }
        let u = elapsed / Profile.landingDuration
        let eased = 1 - pow(1 - u, 3)       // ease-out, as --ease-out 0.22,1,0.36,1 approximates
        let x = l.from.x + (target.x - l.from.x) * CGFloat(eased)
        let y = l.from.y + (target.y - l.from.y) * CGFloat(eased)
        return (CGPoint(x: x, y: y), u)
    }
}

enum ProfileMode: Equatable {
    case running, idle, paused, failed
}

/// The approach profile (docs/design.md, section 1). A glide slope from the top left to a runway on the right.
struct ApproachProfile: View {
    let marks: [ProfileMark]
    let mode: ProfileMode
    let hovered: String?
    let justLanded: Set<String>
    let motion: ProfileMotion
    var onHover: (String?) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let drift: CGFloat = 6        // circles move down the slope by at most 6 pt
    private static let driftLoop = 4.0           // seconds per loop

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : nil)) { context in
            Canvas { gc, _ in
                draw(&gc, now: context.date)
            }
        }
        .frame(width: Profile.width, height: Profile.height)
        .overlay(alignment: .topLeading) { ticks }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): onHover(nearest(to: point))
            case .ended: onHover(nil)
            }
        }
    }

    /// Stage ticks above the slope: the legend.
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
            .font(.system(size: 11))
            .foregroundStyle(Palette(scheme).secondary)
            .offset(x: x, y: 0)
    }

    private func nearest(to p: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for pm in Profile.place(marks) {
            let d = hypot(pm.centre.x - p.x, pm.centre.y - p.y)
            if d < 10, best == nil || d < best!.1 { best = (pm.id, d) }
        }
        return best?.0
    }

    private func draw(_ gc: inout GraphicsContext, now: Date) {
        let p = Palette(scheme)
        let t = now.timeIntervalSinceReferenceDate
        let placed = Profile.place(marks)
        let alpha: Double = mode == .paused ? 0.4 : 1
        motion.advance(placed, justLanded: justLanded, now: now, reduce: reduceMotion)

        // Glide slope and runway.
        var slope = Path()
        slope.move(to: Profile.slopeStart)
        slope.addLine(to: Profile.slopeEnd)
        gc.stroke(slope, with: .color(p.secondary.opacity(alpha)), lineWidth: 1.5)
        let runway = CGRect(x: Profile.runwayX, y: Profile.runwayY, width: Profile.runwayLength, height: Profile.runwayHeight)
        gc.fill(Path(runway), with: .color(mode == .failed ? p.error.opacity(0.6) : p.runway.opacity(alpha)))
        if mode == .failed {
            var cross = Path()
            cross.move(to: CGPoint(x: 267, y: 41)); cross.addLine(to: CGPoint(x: 273, y: 47))
            cross.move(to: CGPoint(x: 273, y: 41)); cross.addLine(to: CGPoint(x: 267, y: 47))
            gc.stroke(cross, with: .color(p.error), lineWidth: 1.5)
        }
        if mode == .paused {
            for x in [CGFloat(0), 4] {
                gc.fill(Path(CGRect(x: x, y: 15, width: 2, height: 8)), with: .color(p.secondary))
            }
        }

        // Marks.
        let halo = placed.first(where: \.isActive)?.id
        for pm in placed {
            // Circles slide along the slope by at most 6 pt and back, toward their next tick.
            let drift: CGFloat = (mode == .running && pm.isActive && !reduceMotion)
                ? Self.drift * CGFloat(1 - cos(2 * Double.pi * t / Self.driftLoop)) / 2 : 0
            let drawn = mark(pm, drift: drift, p: p, alpha: alpha)
            if let landing = motion.landing(pm.id, target: pm.centre, now: now) {
                let colour = landing.progress < 0.6 ? p.doingMark : verdictColour(pm.kind, p)
                gc.fill(Path(ellipseIn: CGRect(x: landing.point.x - 4, y: landing.point.y - 4, width: 8, height: 8)),
                        with: .color(colour))
            } else {
                draw(drawn, in: &gc)
            }
            if pm.id == halo, mode == .running {
                let c = drawn.centre
                gc.stroke(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)),
                          with: .color(p.doingMark), lineWidth: 2)
            }
            if hovered == pm.id {
                let c = drawn.centre
                gc.stroke(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                          with: .color(p.ink), lineWidth: 1)
            }
        }
    }

    private struct Drawn {
        let centre: CGPoint
        let side: CGFloat
        let colour: Color
    }

    private func mark(_ pm: PlacedMark, drift: CGFloat, p: Palette, alpha: Double) -> Drawn {
        let slides = pm.isActive || pm.kind == .queued
        let x = min(pm.centre.x + drift, Profile.slopeEnd.x - 6)
        let centre = slides ? CGPoint(x: x, y: Profile.slopeY(x)) : pm.centre
        switch pm.kind {
        case .active:
            return Drawn(centre: centre, side: 0, colour: p.doingMark.opacity(alpha))
        case .queued:
            return Drawn(centre: centre, side: 0, colour: p.greyMark.opacity(alpha))
        case .landed(let verdict):
            return Drawn(centre: centre, side: pm.side, colour: verdictColour(.landed(verdict), p).opacity(alpha))
        case .dropped:
            return Drawn(centre: centre, side: pm.side, colour: p.greyMark.opacity(alpha))
        }
    }

    private func verdictColour(_ kind: MarkKind, _ p: Palette) -> Color {
        switch kind {
        case .landed(.changes): return p.amber
        case .landed(.approve): return p.approveMark
        case .landed(.skipped), .dropped, .queued, .active: return p.greyMark
        }
    }

    private func draw(_ d: Drawn, in gc: inout GraphicsContext) {
        if d.side == 0 {
            gc.fill(Path(ellipseIn: CGRect(x: d.centre.x - 4, y: d.centre.y - 4, width: 8, height: 8)), with: .color(d.colour))
        } else {
            let rect = CGRect(x: d.centre.x - d.side / 2, y: d.centre.y - d.side / 2, width: d.side, height: d.side)
            gc.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(d.colour))
        }
    }
}
