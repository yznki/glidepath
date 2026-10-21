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
    /// Carried over from an earlier sweep: drawn in tertiary grey.
    var carried = false
}

/// A mark with its position worked out. Pure, so the layout rules can be tested.
struct PlacedMark: Equatable {
    let id: String
    let kind: MarkKind
    let label: String
    let carried: Bool
    /// Circles: the centre on the slope. Landed marks: the centre on the runway.
    let centre: CGPoint
    /// Landed marks: their size (10 pt, smaller only when more than five land).
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

/// Geometry of the approach profile, in points, origin top left (docs/design.md, pass 4).
enum Profile {
    /// Full width in every state.
    static let width: CGFloat = 328
    static let runningHeight: CGFloat = 64
    static let quietHeight: CGFloat = 36

    /// Running: the slope from (0, 36) to (268, 52), stage labels above it (clear of the tick row), the runway at y = 52.
    static let runningSlopeStart = CGPoint(x: 0, y: 36)
    static let runningSlopeEnd = CGPoint(x: 268, y: 52)
    static let runningRunwayTop: CGFloat = 52
    /// Quiet states: the slope runs the full width to the runway at y = 30; no labels, no dots.
    static let quietSlopeStart = CGPoint(x: 0, y: 6)
    static let quietSlopeEnd = CGPoint(x: 268, y: 30)
    static let quietRunwayTop: CGFloat = 30

    static let runwayX: CGFloat = 268
    static let runwayLength: CGFloat = 60
    /// The runway is a 2 pt bar.
    static let runwayBar: CGFloat = 2

    static let markSide: CGFloat = 10
    /// Landed marks: 10 pt, 6 pt apart, the first aligned under "land".
    static let markStep: CGFloat = 16
    static let inFlightDiameter: CGFloat = 10
    static let spread: CGFloat = 11
    static let landingDuration: Double = 0.7

    static func runwayTop(running: Bool) -> CGFloat {
        running ? runningRunwayTop : quietRunwayTop
    }

    static func runningSlopeY(_ x: CGFloat) -> CGFloat {
        runningSlopeStart.y + x / runningSlopeEnd.x * (runningSlopeEnd.y - runningSlopeStart.y)
    }

    /// Centre x of stage n (1...4) on the slope: the middle of its quarter.
    static func stageX(_ n: Int) -> CGFloat {
        (CGFloat(min(max(n, 1), 4)) - 0.5) / 4 * runningSlopeEnd.x
    }

    /// Places every mark. Running circles spread 11 pt apart along the slope within their stage. Landed marks sit
    /// on the runway in list order, the first aligned under "land". More than four shrink the spacing so they still
    /// fit the 60 pt runway; past six they shrink too.
    static func place(_ marks: [ProfileMark], running: Bool) -> [PlacedMark] {
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
        if running {
            for (stage, group) in byStage {
                for (k, m) in group.enumerated() {
                    let offset = CGFloat(k) - CGFloat(group.count - 1) / 2
                    let x = min(max(stageX(stage) + offset * spread, 0), runningSlopeEnd.x - 6)
                    out.append(PlacedMark(id: m.id, kind: m.kind, label: m.label, carried: m.carried,
                                          centre: CGPoint(x: x, y: runningSlopeY(x)), side: inFlightDiameter))
                }
            }
            for (k, m) in queued.enumerated() {
                let x = min(CGFloat(k) * spread + 4, runningSlopeEnd.x - 6)
                out.append(PlacedMark(id: m.id, kind: m.kind, label: m.label, carried: m.carried,
                                      centre: CGPoint(x: x, y: runningSlopeY(x)), side: markSide))
            }
        }
        let count = landed.count
        let step: CGFloat = count <= 4 ? markStep : (count <= 1 ? markStep : (runwayLength - markSide) / CGFloat(count - 1))
        let side: CGFloat = step >= 12 ? markSide : max(min(markSide, step - 2), 4)
        let top = runwayTop(running: running)
        for (k, m) in landed.enumerated() {
            let left = runwayX + CGFloat(k) * step
            out.append(PlacedMark(id: m.id, kind: m.kind, label: m.label, carried: m.carried,
                                  centre: CGPoint(x: left + side / 2, y: top - side / 2), side: side))
        }
        return out
    }

    /// Radius of a placed mark, for the hover ring.
    static func radius(_ pm: PlacedMark) -> CGFloat {
        pm.isActive ? inFlightDiameter / 2 : pm.side / 2
    }
}

/// Per-frame motion for the profile: in-flight circles drift along the slope, landings slide onto the runway. Not
/// SwiftUI state, so animating it does not re-render the view tree.
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
    /// A sweep is in progress: the full 64 pt profile with stage labels and numbered dots.
    case running
    /// Idle with a last run: the 36 pt profile with landed marks.
    case idle
    /// Paused: the 36 pt profile at 40%, pause glyph at the runway's end.
    case paused
    /// A run that did not finish: the 36 pt profile, the runway in error colour, a red cross at the touchdown point.
    case failed
    /// No run yet, or no PRs: the 36 pt profile with a dashed slope at 50% and an empty runway.
    case empty
}

/// The approach profile (docs/design.md, pass 4). It is present in every state at full width.
struct ApproachProfile: View {
    let marks: [ProfileMark]
    let mode: ProfileMode
    let hovered: String?
    let justLanded: Set<String>
    let motion: ProfileMotion
    var onHover: (String?) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let drift: CGFloat = 6
    private static let driftLoop = 4.0

    var body: some View {
        let height = mode == .running ? Profile.runningHeight : Profile.quietHeight
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : nil)) { context in
            Canvas { gc, _ in
                draw(&gc, now: context.date)
            }
        }
        .frame(width: Profile.width, height: height)
        .overlay(alignment: .topLeading) {
            if mode == .running { ticks }
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

    private var running: Bool { mode == .running }

    private func nearest(to p: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for pm in Profile.place(marks, running: running) {
            let d = hypot(pm.centre.x - p.x, pm.centre.y - p.y)
            if d < 10, best == nil || d < best!.1 { best = (pm.id, d) }
        }
        return best?.0
    }

    /// Numbered labels: one per cluster of in-flight dots. A cluster shows its hovered dot, or else its most advanced
    /// PR (the most recent activity). Labels are always above their dot.
    private func labelled(_ placed: [PlacedMark]) -> Set<String> {
        let dots = placed.filter(\.isActive).sorted { $0.centre.x < $1.centre.x }
        var clusters: [[PlacedMark]] = []
        for dot in dots {
            if let last = clusters.last?.last, abs(dot.centre.x - last.centre.x) < 36 {
                clusters[clusters.count - 1].append(dot)
            } else {
                clusters.append([dot])
            }
        }
        var shown: Set<String> = []
        for cluster in clusters {
            if let hover = cluster.first(where: { $0.id == hovered }) {
                shown.insert(hover.id)
            } else if let best = cluster.max(by: { stage($0) < stage($1) }) {
                shown.insert(best.id)
            }
        }
        return shown
    }

    private func stage(_ pm: PlacedMark) -> Int {
        if case .active(let s) = pm.kind { return s }
        return 0
    }

    private func draw(_ gc: inout GraphicsContext, now: Date) {
        let p = Palette(scheme)
        let t = now.timeIntervalSinceReferenceDate
        let placed = Profile.place(marks, running: running)
        let alpha: Double = mode == .paused ? 0.4 : 1
        motion.advance(placed, justLanded: justLanded, now: now, reduce: reduceMotion)
        let top = Profile.runwayTop(running: running)

        // Slope.
        var slope = Path()
        switch mode {
        case .running:
            slope.move(to: Profile.runningSlopeStart)
            slope.addLine(to: Profile.runningSlopeEnd)
        default:
            slope.move(to: Profile.quietSlopeStart)
            slope.addLine(to: Profile.quietSlopeEnd)
        }
        if mode == .empty {
            gc.stroke(slope, with: .color(p.slope.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        } else {
            gc.stroke(slope, with: .color(p.slope.opacity(alpha)), lineWidth: 2)
        }

        // Runway: a 2 pt grey bar in every state.
        let runway = CGRect(x: Profile.runwayX, y: top, width: Profile.runwayLength, height: Profile.runwayBar)
        gc.fill(Path(runway), with: .color(p.runwayBar.opacity(alpha)))

        // Failed: a red cross at the touchdown point. Paused: the pause glyph at the runway's end.
        if mode == .failed {
            var cross = Path()
            // Just short of the runway: the touchdown point, clear of the first landed mark.
            let c = CGPoint(x: Profile.runwayX - 6, y: top - 5)
            cross.move(to: CGPoint(x: c.x - 5, y: c.y - 5)); cross.addLine(to: CGPoint(x: c.x + 5, y: c.y + 5))
            cross.move(to: CGPoint(x: c.x + 5, y: c.y - 5)); cross.addLine(to: CGPoint(x: c.x - 5, y: c.y + 5))
            gc.stroke(cross, with: .color(p.error), lineWidth: 2)
        }
        if mode == .paused {
            for x in [CGFloat(316), 322] {
                gc.fill(Path(CGRect(x: x, y: top - 10, width: 2, height: 8)), with: .color(p.secondary))
            }
        }

        // Numbered labels for in-flight dots, shown per cluster.
        let shownLabels = labelled(placed)

        for pm in placed {
            let drift: CGFloat = (running && pm.isActive && !reduceMotion)
                ? Self.drift * CGFloat(1 - cos(2 * Double.pi * t / Self.driftLoop)) / 2 : 0
            let drawn = mark(pm, drift: drift, p: p, alpha: alpha)
            if let landing = motion.landing(pm.id, target: pm.centre, now: now) {
                let colour = landing.progress < 0.6 ? p.doingMark : markColour(pm.kind, p)
                gc.fill(Path(ellipseIn: CGRect(x: landing.point.x - 5, y: landing.point.y - 5, width: 10, height: 10)),
                        with: .color(colour))
            } else {
                draw(drawn, in: &gc)
            }
            if pm.isActive, shownLabels.contains(pm.id) {
                let text = Text(pm.label).font(.system(size: 11, weight: .medium)).foregroundStyle(p.tertiary)
                gc.draw(text, at: CGPoint(x: drawn.centre.x, y: drawn.centre.y - 11), anchor: .bottom)
            }
            if hovered == pm.id {
                let r = Profile.radius(pm) + 5
                gc.stroke(Path(ellipseIn: CGRect(x: drawn.centre.x - r, y: drawn.centre.y - r, width: 2 * r, height: 2 * r)),
                          with: .color(markColour(pm.kind, p)), lineWidth: 2)
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
        let x = min(pm.centre.x + drift, Profile.runningSlopeEnd.x - 6)
        let centre = slides ? CGPoint(x: x, y: Profile.runningSlopeY(x)) : pm.centre
        let colour = pm.carried ? p.tertiary : markColour(pm.kind, p)
        return Drawn(centre: centre, side: pm.side, colour: colour.opacity(alpha), kind: pm.kind)
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
