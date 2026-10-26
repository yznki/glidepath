import SwiftUI
import AppKit

/// What the glide line draws for a state (spec §9). Pure, so the mapping is tested.
struct LineLook: Equatable {
    enum Stroke: Equatable { case solid, dotted }
    enum Motion: Equatable { case still, breath, tracer }

    /// Amber beads: one per Needs-you item, up to `maxBeads`.
    var beads = 0
    var stroke = Stroke.solid
    /// A gap in the middle that holds the Fix button.
    var broken = false
    /// Holding back: dotted like a pause, but dimmer, because Glidepath chose it, not you.
    var dim = false
    var motion = Motion.still

    /// Past this the line would crowd; the count beside the title says the rest.
    static let maxBeads = 8

    static func of(_ state: GlideState, reduceMotion: Bool = false) -> LineLook {
        var look = LineLook()
        switch state {
        case .quiet: look.motion = .breath
        case .checking: look.motion = .tracer
        case .needs(let count): look.beads = min(max(count, 0), maxBeads)
        case .problem: look.broken = true
        case .paused: look.stroke = .dotted
        case .holdingBack: look.stroke = .dotted; look.dim = true
        }
        if reduceMotion { look.motion = .still }
        return look
    }
}

/// Where the line lives: under the window title, or across the top of the popover.
enum GlideSize {
    case header, popover

    var height: CGFloat { self == .header ? 34 : 22 }
    var bead: CGFloat { self == .header ? 7 : 6 }
    var beadGap: CGFloat { self == .header ? 22 : 15 }
    var beadStart: CGFloat { self == .header ? 40 : 26 }
    var baseInset: CGFloat { self == .header ? 7 : 5 }
    var maxLift: CGFloat { self == .header ? 14 : 9 }
    var runTail: CGFloat { self == .header ? 70 : 34 }
    var lineWidth: CGFloat { self == .header ? 1.5 : 1.2 }
    var glowWidth: CGFloat { self == .header ? 5 : 3 }
    var glowBlur: CGFloat { self == .header ? 4 : 2.5 }
    var gapHalf: CGFloat { self == .header ? 44 : 34 }
    var edgeFade: CGFloat { self == .header ? 28 : 14 }
}

/// The one living object in the app: the path a glider takes down to land. Driven only by the glide state.
/// Quiet: flat, one slow breath every few seconds. Checking: a tracer of light runs along it. Needs you: amber beads
/// on an approach that lifts with the count. Problem: a gap that holds `fix`. Paused and holding back: dotted.
/// Motion runs only while a state needs it, through `TimelineView`; Reduce Motion turns it off and cross-fades.
struct GlideLine<Fix: View>: View {
    let state: GlideState
    var size: GlideSize
    let fix: Fix

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var memory = LineMemory()

    init(_ state: GlideState, size: GlideSize = .header, @ViewBuilder fix: () -> Fix) {
        self.state = state
        self.size = size
        self.fix = fix()
    }

    var body: some View {
        let look = LineLook.of(state, reduceMotion: reduceMotion)
        GeometryReader { g in
            let path = path(look, width: g.size.width, height: g.size.height)
            ZStack(alignment: .topLeading) {
                line(path, look: look, width: g.size.width)
                if look.motion == .tracer {
                    GlideTracer(path: path, size: size)
                }
                ForEach(0..<look.beads, id: \.self) { i in
                    let x = size.beadStart + CGFloat(i) * size.beadGap
                    Circle()
                        .fill(Color.amber)
                        .frame(width: size.bead, height: size.bead)
                        .shadow(color: Color.amber.opacity(0.9), radius: size == .header ? 5 : 3)
                        .position(x: x, y: path.y(at: x))
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.2).combined(with: .opacity),
                            removal: .offset(x: 22, y: 9).combined(with: .scale(scale: 0.3)).combined(with: .opacity)))
                }
                if look.broken {
                    fix
                        .position(x: g.size.width / 2, y: path.baseline)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: size.height)
        .animation(reduceMotion ? .fade : .glide, value: look)
        .onChange(of: look.beads) { old, new in
            if old > 0 && new == 0 { memory.touchdowns += 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.status(state))
    }

    private func path(_ look: LineLook, width: CGFloat, height: CGFloat) -> GlidePath {
        let n = CGFloat(look.beads)
        return GlidePath(baseline: height - size.baseInset,
                         lift: n == 0 ? 0 : min(5 + 2.6 * n, size.maxLift),
                         run: size.beadStart + max(n, 1) * size.beadGap + size.runTail,
                         gapCenter: width / 2,
                         gapHalf: look.broken ? size.gapHalf : 0)
    }

    /// Solid and dotted are both drawn and cross-faded, so every change between states is a fade, never a jump.
    @ViewBuilder private func line(_ path: GlidePath, look: LineLook, width: CGFloat) -> some View {
        let ink = LinearGradient(stops: fadeStops(width: width), startPoint: .leading, endPoint: .trailing)
        let stack = ZStack {
            path.stroke(ink, style: StrokeStyle(lineWidth: size.glowWidth, lineCap: .round))
                .blur(radius: size.glowBlur)
                .opacity(look.stroke == .solid ? 0.45 : 0)
            path.stroke(ink, style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round))
                .opacity(look.stroke == .solid ? 1 : 0)
            path.stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.01, 6]))
                .opacity(look.stroke == .dotted ? (look.dim ? 0.55 : 1) : 0)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: memory.touchdowns) { content, flash in
            content.brightness(flash * 0.5)
        } keyframes: { _ in
            CubicKeyframe(1, duration: 0.35)
            CubicKeyframe(0, duration: 1.6)
        }
        stack
            .opacity(look.motion == .breath ? 0.75 : 0.85)
            .overlay {
                if look.motion == .breath {
                    BreathGlow(baseline: path.baseline, size: size)
                }
            }
    }

    /// The line fades in at the left and out at the right.
    private func fadeStops(width: CGFloat) -> [Gradient.Stop] {
        let edge = min(size.edgeFade / max(width, 1), 0.2)
        let lit = Color.white.opacity(0.85)
        return [.init(color: .clear, location: 0), .init(color: lit, location: edge),
                .init(color: lit, location: 1 - edge), .init(color: .clear, location: 1)]
    }
}

extension GlideLine where Fix == EmptyView {
    init(_ state: GlideState, size: GlideSize = .header) {
        self.init(state, size: size) { EmptyView() }
    }
}

/// Counts touchdowns (Needs you reaching zero) so the line can brighten once.
final class LineMemory: ObservableObject {
    @Published var touchdowns = 0
}

/// One slow breath of light along the quiet line every few seconds. The quiet line is flat, so the breath is a lit bar
/// at the baseline whose opacity Core Animation runs in the render server: the app itself draws nothing while it breathes.
private struct BreathGlow: NSViewRepresentable {
    let baseline: CGFloat
    let size: GlideSize

    static let period: CFTimeInterval = 6
    static let breath: CFTimeInterval = 2.2

    func makeNSView(context: Context) -> BreathView { BreathView() }

    func updateNSView(_ view: BreathView, context: Context) {
        view.baseline = baseline
        view.size = size
        view.needsLayout = true
    }

    final class BreathView: NSView {
        var baseline: CGFloat = 0
        var size = GlideSize.header
        private let glow = CAGradientLayer()
        private let core = CAGradientLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for bar in [glow, core] {
                bar.startPoint = CGPoint(x: 0, y: 0.5)
                bar.endPoint = CGPoint(x: 1, y: 0.5)
                bar.opacity = 0
                layer?.addSublayer(bar)
            }
            glow.shadowColor = .white
            glow.shadowOpacity = 1
            glow.shadowOffset = .zero
        }

        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            let edge = NSNumber(value: Double(min(size.edgeFade / max(bounds.width, 1), 0.2)))
            let white = NSColor.white.cgColor, clear = NSColor.white.withAlphaComponent(0).cgColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (bar, height) in [(glow, size.glowWidth), (core, size.lineWidth)] {
                bar.colors = [clear, white, white, clear]
                bar.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
                bar.frame = CGRect(x: 0, y: baseline - height / 2, width: bounds.width, height: height)
                bar.cornerRadius = height / 2
            }
            glow.shadowRadius = size.glowBlur
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            for (bar, peak) in [(glow, 0.3), (core, 0.45)] {
                let pulse = CAKeyframeAnimation(keyPath: "opacity")
                let top = BreathGlow.breath / 2 / BreathGlow.period, end = BreathGlow.breath / BreathGlow.period
                pulse.values = [0, peak, 0, 0]
                pulse.keyTimes = [0, NSNumber(value: top), NSNumber(value: end), 1]
                pulse.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
                pulse.duration = BreathGlow.period
                pulse.repeatCount = .infinity
                pulse.isRemovedOnCompletion = false
                bar.add(pulse, forKey: "breath")
            }
        }
    }
}

/// A soft light gliding left to right along the line while a check runs. 30 fps, only in the checking state.
private struct GlideTracer: View {
    let path: GlidePath
    let size: GlideSize
    static let period = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            let p = t * t * (3 - 2 * t)             // ease in and out: it glides, never jerks
            let tail = size == .header ? 0.16 : 0.28
            let ink = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.9),
                                             .init(color: .clear, location: 1)],
                                     startPoint: UnitPoint(x: p * 1.2 - tail, y: 0.5),
                                     endPoint: UnitPoint(x: p * 1.2 + 0.015, y: 0.5))
            ZStack {
                path.stroke(ink, style: StrokeStyle(lineWidth: size.glowWidth + 2, lineCap: .round))
                    .blur(radius: size.glowBlur + 2)
                path.stroke(ink, style: StrokeStyle(lineWidth: size.lineWidth + 0.5, lineCap: .round))
            }
            .opacity(sin(.pi * t) * 0.9 + 0.1)
        }
        .allowsHitTesting(false)
    }
}

/// The glide path: an approach that eases down from `lift` and lies flat after `run`.
/// An optional gap breaks the line around `gapCenter`.
struct GlidePath: Shape {
    var baseline: CGFloat
    var lift: CGFloat
    var run: CGFloat
    var gapCenter: CGFloat = 0
    var gapHalf: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(lift, AnimatablePair(run, gapHalf)) }
        set { lift = newValue.first; run = newValue.second.first; gapHalf = newValue.second.second }
    }

    func y(at x: CGFloat) -> CGFloat {
        guard x < run, run > 0 else { return baseline }
        return baseline - lift * 0.5 * (1 + cos(.pi * x / run))
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var drawing = false
        for x in stride(from: 0, through: rect.width, by: 2) {
            if gapHalf > 0.5 && abs(x - gapCenter) < gapHalf { drawing = false; continue }
            let pt = CGPoint(x: x, y: y(at: x))
            if drawing { p.addLine(to: pt) } else { p.move(to: pt); drawing = true }
        }
        return p
    }
}

// MARK: - Menu bar glyph

/// The line as a template image for the status item: a flat approach (quiet), a dot travelling it (checking), a dot
/// at its start (needs you; the count goes in the button title beside it), broken (problem), dotted (paused, holding
/// back). Images are cached: the status item redraws whenever it gets a new image object.
@MainActor
enum GlideGlyph {
    static let size = NSSize(width: 24, height: 16)
    /// Frames in one pass of the checking dot. Under Reduce Motion pass a fixed `phase`.
    static let frames = 24

    private enum Shape: Hashable { case flat, dot(frame: Int), bead, broken, dotted }
    private static var cache: [Shape: NSImage] = [:]

    /// `phase` (0..<1) places the checking dot along the line; other states ignore it.
    static func image(for state: GlideState, phase: Double = 0) -> NSImage {
        let look = LineLook.of(state)
        let shape: Shape
        if case .checking = state {
            let t = phase - floor(phase)
            shape = .dot(frame: Int(t * Double(frames)) % frames)
        } else if look.beads > 0 {
            shape = .bead
        } else if look.broken {
            shape = .broken
        } else if look.stroke == .dotted {
            shape = .dotted
        } else {
            shape = .flat
        }
        if let image = cache[shape] { return image }
        let image = draw(shape)
        cache[shape] = image
        return image
    }

    private static func draw(_ shape: Shape) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            let path = GlidePath(baseline: 12, lift: 7, run: 13)
            func pt(_ x: CGFloat) -> CGPoint { CGPoint(x: x, y: path.y(at: x)) }
            let line = NSBezierPath()
            line.lineWidth = 2
            line.lineCapStyle = .round
            var x: CGFloat = 2
            line.move(to: pt(x))
            while x < 22 {
                x += 1
                if shape == .broken && x == 14 { x = 17; line.move(to: pt(x)); continue }
                line.line(to: pt(x))
            }
            if shape == .dotted { line.setLineDash([0.01, 3.2], count: 2, phase: 0) }
            line.stroke()
            var dot: CGPoint?
            if case .dot(let frame) = shape { dot = pt(2 + 20 * CGFloat(frame) / CGFloat(frames)) }
            if shape == .bead { dot = pt(5) }
            if let c = dot {
                NSBezierPath(ovalIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glidepath"
        return image
    }
}
