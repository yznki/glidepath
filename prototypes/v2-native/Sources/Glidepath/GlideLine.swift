import SwiftUI
import AppKit

/// The one living object in the app: the path a glider takes down to land.
/// Driven only by the store. Beads are the Needs you items; the line's approach shortens as they land.
struct GlideLine: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false

    @State private var touchdown = 0

    private var bead: CGFloat { compact ? 6 : 7 }
    private var beadGap: CGFloat { compact ? 15 : 22 }
    private var beadStart: CGFloat { compact ? 26 : 40 }
    private var gapHalf: CGFloat { store.lineMode == .problem ? (compact ? 34 : 44) : 0 }

    var body: some View {
        GeometryReader { g in
            let n = store.needsCount
            let base = g.size.height - (compact ? 5 : 7)
            let lift: CGFloat = n == 0 ? 0 : min(5 + 2.6 * CGFloat(n), compact ? 9 : 14)
            let run: CGFloat = beadStart + CGFloat(max(n, 1)) * beadGap + (compact ? 34 : 70)
            let path = GlidePath(baseline: base, lift: lift, run: run, gapCenter: g.size.width / 2, gapHalf: gapHalf)

            ZStack(alignment: .topLeading) {
                line(path, width: g.size.width)
                if store.lineMode == .checking && !reduceMotion {
                    Tracer(path: path, started: store.checkStarted, period: store.checkPeriod, compact: compact)
                }
                ForEach(Array(store.needsYou.enumerated()), id: \.element.id) { i, pr in
                    let x = beadStart + CGFloat(i) * beadGap
                    Circle()
                        .fill(Color.amber)
                        .frame(width: bead, height: bead)
                        .shadow(color: Color.amber.opacity(0.9), radius: compact ? 3 : 5)
                        .position(x: x, y: path.y(at: x))
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.2).combined(with: .opacity),
                            removal: .offset(x: 22, y: 9).combined(with: .scale(scale: 0.3)).combined(with: .opacity)))
                        .help("\(pr.need?.label ?? "") · \(pr.shortRef)")
                }
                if store.lineMode == .problem {
                    Button { store.primary() } label: {
                        Label("Fix", systemImage: "exclamationmark.triangle.fill")
                            .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                            .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 2 : 4)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .position(x: g.size.width / 2, y: base)
                    .transition(.opacity)
                }
            }
        }
        .frame(height: compact ? 22 : 34)
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .glide, value: store.needsCount)
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .glide, value: store.lineMode)
        .onChange(of: store.needsCount) { old, new in if old > 0 && new == 0 { touchdown += 1 } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.status.text)
    }

    /// Flat, dotted or broken; breathes once every few seconds when quiet; brightens once on touchdown.
    @ViewBuilder private func line(_ path: GlidePath, width: CGFloat) -> some View {
        let paused = store.lineMode == .paused
        let style = StrokeStyle(lineWidth: paused ? 2 : (compact ? 1.2 : 1.5), lineCap: .round, dash: paused ? [0.01, 6] : [])
        let ink = LinearGradient(stops: fadeStops(width: width, path: path), startPoint: .leading, endPoint: .trailing)
        let stack = ZStack {
            path.stroke(ink, style: StrokeStyle(lineWidth: compact ? 3 : 5, lineCap: .round, dash: style.dash))
                .blur(radius: compact ? 2.5 : 4)
                .opacity(0.45)
            path.stroke(ink, style: style)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: touchdown) { content, flash in
            content.brightness(flash * 0.5).opacity(0.7 + flash * 0.3)
        } keyframes: { _ in
            CubicKeyframe(1, duration: 0.35)
            CubicKeyframe(0, duration: 1.6)
        }
        if store.lineMode == .quiet && !reduceMotion {
            stack.phaseAnimator([0.0, 0.0, 1.0]) { content, breath in
                content.brightness(breath * 0.35).opacity(0.75 + breath * 0.25)
            } animation: { breath in
                breath == 1 ? .easeInOut(duration: 1.4) : .easeInOut(duration: 2.2)
            }
        } else {
            stack
        }
    }

    private func fadeStops(width: CGFloat, path: GlidePath) -> [Gradient.Stop] {
        let w = max(width, 1), edge = min((compact ? 14 : 28) / w, 0.2)
        let lit = Color.white.opacity(0.85)
        var stops: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: lit, location: edge)]
        if store.lineMode == .problem {
            let c = path.gapCenter / w, g = gapHalf / w, soft = 12 / w
            stops += [.init(color: lit, location: c - g - soft), .init(color: .white.opacity(0.15), location: c - g),
                      .init(color: .white.opacity(0.15), location: c + g), .init(color: lit, location: c + g + soft)]
        }
        stops += [.init(color: lit, location: 1 - edge), .init(color: .clear, location: 1)]
        return stops
    }
}

/// A soft light gliding left to right, once per PR being checked.
private struct Tracer: View {
    let path: GlidePath
    let started: Date
    let period: Double
    let compact: Bool

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(started).truncatingRemainder(dividingBy: period) / period
            let p = t * t * (3 - 2 * t)             // ease in and out: it glides, never jerks
            let tail = compact ? 0.28 : 0.16
            let ink = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.9), .init(color: .clear, location: 1)],
                                     startPoint: UnitPoint(x: p * 1.2 - tail, y: 0.5), endPoint: UnitPoint(x: p * 1.2 + 0.015, y: 0.5))
            ZStack {
                path.stroke(ink, style: StrokeStyle(lineWidth: compact ? 4 : 7, lineCap: .round)).blur(radius: compact ? 3 : 6)
                path.stroke(ink, style: StrokeStyle(lineWidth: compact ? 1.6 : 2, lineCap: .round))
            }
            .opacity(sin(.pi * t) * 0.9 + 0.1)
        }
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

extension Animation {
    /// "Glide and settle": a long ease-out spring with no bounce.
    static let glide = Animation.spring(duration: 0.9, bounce: 0)
}

// MARK: - Menu bar glyph

/// The line itself as a template image: flat approach (quiet), a dot travelling it (checking),
/// broken (problem), dotted (paused). The count sits beside it as text.
@MainActor enum LineGlyph {
    /// Cached: the status item redraws whenever it sees a new image object.
    private static let still: [LineMode: NSImage] = Dictionary(uniqueKeysWithValues: [LineMode.quiet, .needs, .problem, .paused].map { ($0, image(mode: $0)) })
    private static let frames: [NSImage] = (0..<24).map { image(mode: .checking, phase: Double($0) / 24) }

    static func cached(mode: LineMode, phase: Double = 0) -> NSImage {
        guard mode == .checking else { return still[mode]! }
        let t = phase - floor(phase)
        return frames[Int(t * 24) % 24]
    }

    static func image(mode: LineMode, phase: Double = 0) -> NSImage {
        let img = NSImage(size: NSSize(width: 24, height: 16), flipped: true) { r in
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
                if mode == .problem && x == 14 { line.move(to: CGPoint(x: 17, y: 12)); x = 17; continue }
                line.line(to: pt(x))
            }
            if mode == .paused { line.setLineDash([0.01, 3.2], count: 2, phase: 0) }
            line.stroke()
            if mode == .checking {
                let t = phase - floor(phase)
                let c = pt(2 + 20 * CGFloat(t))
                NSBezierPath(ovalIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)).fill()
            } else if mode == .needs {
                let c = pt(5)
                NSBezierPath(ovalIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)).fill()
            }
            _ = r
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Glidepath"
        return img
    }
}

extension LineGlyph {
    /// Prototype only: the five menu bar states side by side, as white on a dark menu bar, at 4x.
    static func sheet(to path: String) {
        let states: [(LineMode, String, String)] = [(.quiet, "", "Quiet"), (.checking, "", "Checking"), (.needs, "4", "Needs you"), (.problem, "", "Problem"), (.paused, "", "Paused")]
        let cell = CGSize(width: 74, height: 40), scale: CGFloat = 4
        let size = CGSize(width: cell.width * CGFloat(states.count), height: cell.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.13, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        for (i, st) in states.enumerated() {
            let x = CGFloat(i) * cell.width
            let glyph = image(mode: st.0, phase: 0.45)
            let tinted = NSImage(size: glyph.size, flipped: false) { r in
                glyph.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
            }
            let w = glyph.size.width + (st.1.isEmpty ? 0 : 10)
            tinted.draw(in: NSRect(x: x + (cell.width - w) / 2, y: 18, width: glyph.size.width, height: glyph.size.height))
            if !st.1.isEmpty {
                (st.1 as NSString).draw(at: NSPoint(x: x + (cell.width - w) / 2 + glyph.size.width + 2, y: 18),
                                        withAttributes: [.font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.white])
            }
            let label = st.2 as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor(white: 1, alpha: 0.5)]
            label.draw(at: NSPoint(x: x + (cell.width - label.size(withAttributes: attrs).width) / 2, y: 4), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
