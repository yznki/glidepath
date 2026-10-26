import SwiftUI
import AppKit

/// The menu bar glyph states (docs/design.md, section 7). Everything is a template image: no colour.
enum GlyphState: Equatable {
    case idle
    case running(active: Int)
    case changesWaiting(count: Int)
    case paused
    case failed
}

/// Draws the glyph family: the app icon's mark in miniature, on an 18 pt canvas centred on (9, 9). A disc of
/// horizontal stripes has a slot cut in from the upper left at 24 degrees, ending at the touchdown point T, where a
/// dot sits. Counts are 12 pt semibold, the same in every state.
enum MenuGlyph {
    static let canvas: CGFloat = 18
    static let countFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    private static let centre = NSPoint(x: 9, y: 9)
    private static let radius: CGFloat = 8
    private static let stripeHeight: CGFloat = 1.6
    private static let stripePitch: CGFloat = 3.2
    private static let slotWidth: CGFloat = 3
    private static let slotDir = NSPoint(x: -cos(24 * CGFloat.pi / 180), y: sin(24 * CGFloat.pi / 180))
    /// The touchdown point: the slot's end centre, and where the dot rests.
    private static let touchdown = NSPoint(x: 11.5, y: 6.5)
    private static let dotRadius: CGFloat = 1.1

    /// The glyph in `ink`. `template` marks it for the menu bar; snapshots pass false so the ink shows.
    /// `update` adds the update dot at the top right, in every state.
    static func image(_ state: GlyphState, progress: Double, ink: NSColor, template: Bool, update: Bool = false) -> NSImage {
        let count: Int? = {
            switch state {
            case .running(let n) where n > 0: return n
            case .changesWaiting(let n) where n > 0: return n
            default: return nil
            }
        }()
        let label = count.map { NSAttributedString(string: "\($0)", attributes: [.font: countFont, .foregroundColor: ink]) }
        let width = canvas + (label.map { $0.size().width + 3 } ?? 0)
        let image = NSImage(size: NSSize(width: width, height: canvas), flipped: false) { _ in
            if state == .paused {
                // Paused: the stripes alone, at half strength. No slot, no dot.
                ink.withAlphaComponent(0.5).set()
                stripes()
            } else {
                ink.set()
                stripes()
                cutSlot()
                ink.set()
                switch state {
                case .running:
                    dot(at: runningPoint(progress))
                case .failed:
                    failMark()
                default:
                    dot(at: touchdown)
                }
            }
            if update {
                // The update dot: 3 pt, centred at (16, 16), which clears the disc by about half a point.
                ink.set()
                NSBezierPath(ovalIn: NSRect(x: 14.5, y: 14.5, width: 3, height: 3)).fill()
            }
            label?.draw(at: NSPoint(x: canvas + 3, y: (canvas - label!.size().height) / 2 - 0.5))
            return true
        }
        image.isTemplate = template
        return image
    }

    /// Where the slot's centre line leaves the disc. The running dot starts here and travels to T.
    private static var slotEntry: NSPoint {
        let dx = touchdown.x - centre.x, dy = touchdown.y - centre.y
        let b = dx * slotDir.x + dy * slotDir.y
        let c = dx * dx + dy * dy - radius * radius
        let s = -b + (b * b - c).squareRoot()     // distance from T along the slot to the disc edge
        return NSPoint(x: touchdown.x + s * slotDir.x, y: touchdown.y + s * slotDir.y)
    }

    /// The running dot's position: from the slot's entry (progress 0) to T (progress 1).
    private static func runningPoint(_ progress: Double) -> NSPoint {
        let f = CGFloat(progress - floor(progress))
        let e = slotEntry
        return NSPoint(x: e.x + (touchdown.x - e.x) * f, y: e.y + (touchdown.y - e.y) * f)
    }

    /// Horizontal stripes, five at a 3.2 pt pitch centred on y = 9, clipped to the disc.
    private static func stripes() {
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)).addClip()
        for i in -2...2 {
            let y = centre.y + CGFloat(i) * stripePitch
            NSBezierPath(rect: NSRect(x: 0, y: y - stripeHeight / 2, width: canvas, height: stripeHeight)).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// The slot: a 3 pt capsule from well beyond the disc's upper left edge down to T, cut out of the stripes.
    private static func cutSlot() {
        guard let gc = NSGraphicsContext.current else { return }
        let far = NSPoint(x: touchdown.x + 30 * slotDir.x, y: touchdown.y + 30 * slotDir.y)
        let slot = NSBezierPath()
        slot.move(to: far)
        slot.line(to: touchdown)
        slot.lineWidth = slotWidth
        slot.lineCapStyle = .round
        gc.saveGraphicsState()
        gc.compositingOperation = .clear
        slot.stroke()
        gc.restoreGraphicsState()
    }

    private static func dot(at p: NSPoint) {
        NSBezierPath(ovalIn: NSRect(x: p.x - dotRadius, y: p.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius)).fill()
    }

    /// Failed: a 4 pt cross centred on T, in place of the dot. The slot stays cut.
    private static func failMark() {
        let x = NSBezierPath()
        x.move(to: NSPoint(x: touchdown.x - 2, y: touchdown.y - 2)); x.line(to: NSPoint(x: touchdown.x + 2, y: touchdown.y + 2))
        x.move(to: NSPoint(x: touchdown.x + 2, y: touchdown.y - 2)); x.line(to: NSPoint(x: touchdown.x - 2, y: touchdown.y + 2))
        x.lineWidth = 1.5
        x.lineCapStyle = .round
        x.stroke()
    }
}

/// Drives the moving dot at 10 fps. The timer exists only while a run is in progress.
@MainActor
final class SweepTicker: ObservableObject {
    @Published var progress: Double = 0
    private var timer: Timer?

    func setRunning(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress = (self.progress + 0.05).truncatingRemainder(dividingBy: 1)
            }
        }
    }
}

/// The glyph the user chose in Settings: the glider (the app icon's mark), a dot, or a count of reviews waiting.
enum GlyphStyle: String {
    case glider, dot, count
}

extension MenuGlyph {
    /// The dot style: a disc at the centre. While a sweep runs a smaller dot orbits it at the sweep's progress.
    static func dotImage(_ state: GlyphState, progress: Double, ink: NSColor, template: Bool, badge: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            ink.withAlphaComponent(state == .paused ? 0.5 : 1).set()
            let centre = NSPoint(x: canvas / 2, y: canvas / 2)
            switch state {
            case .failed:
                let x = NSBezierPath()
                x.move(to: NSPoint(x: centre.x - 3, y: centre.y - 3)); x.line(to: NSPoint(x: centre.x + 3, y: centre.y + 3))
                x.move(to: NSPoint(x: centre.x + 3, y: centre.y - 3)); x.line(to: NSPoint(x: centre.x - 3, y: centre.y + 3))
                x.lineWidth = 1.5
                x.lineCapStyle = .round
                x.stroke()
            case .running:
                NSBezierPath(ovalIn: NSRect(x: centre.x - 2.6, y: centre.y - 2.6, width: 5.2, height: 5.2)).fill()
                let angle = CGFloat(progress) * 2 * .pi
                let orbit = NSPoint(x: centre.x + 7 * cos(angle), y: centre.y + 7 * sin(angle))
                NSBezierPath(ovalIn: NSRect(x: orbit.x - 1.3, y: orbit.y - 1.3, width: 2.6, height: 2.6)).fill()
            default:
                NSBezierPath(ovalIn: NSRect(x: centre.x - 3.4, y: centre.y - 3.4, width: 6.8, height: 6.8)).fill()
            }
            if badge { badgeDot(x: 14.5, ink: ink) }
            return true
        }
        image.isTemplate = template
        return image
    }

    /// The count style: the number of reviews waiting, in the glyph's count type.
    static func countImage(_ count: Int, ink: NSColor, template: Bool, badge: Bool) -> NSImage {
        let label = NSAttributedString(string: "\(count)", attributes: [.font: countFont, .foregroundColor: ink])
        let width = ceil(label.size().width) + 2
        let image = NSImage(size: NSSize(width: width, height: canvas), flipped: false) { _ in
            label.draw(at: NSPoint(x: 1, y: (canvas - label.size().height) / 2 - 0.5))
            if badge { badgeDot(x: width - 3.5, ink: ink) }
            return true
        }
        image.isTemplate = template
        return image
    }

    /// The update and review badge: a 3 pt dot at the top right, the same in every style.
    fileprivate static func badgeDot(x: CGFloat, ink: NSColor) {
        ink.set()
        NSBezierPath(ovalIn: NSRect(x: x, y: 14.5, width: 3, height: 3)).fill()
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @StateObject private var ticker = SweepTicker()
    @AppStorage("glyphStyle") private var style = GlyphStyle.glider.rawValue
    @AppStorage("glyphBadge") private var badgeOn = true

    var body: some View {
        // The badge marks an update, or anything that needs the user (when the badge setting is on).
        let badge = store.availableUpdate != nil || (badgeOn && store.needsCount > 0)
        Image(nsImage: image(store.glyph, badge: badge))
            .onAppear { ticker.setRunning(store.snap.running || store.snap.dryRunning) }
            .onChange(of: store.snap.running || store.snap.dryRunning) { _, busy in ticker.setRunning(busy) }
    }

    private func image(_ glyph: GlyphState, badge: Bool) -> NSImage {
        switch GlyphStyle(rawValue: style) ?? .glider {
        case .glider:
            return MenuGlyph.image(glyph, progress: ticker.progress, ink: .black, template: true, update: badge)
        case .dot:
            return MenuGlyph.dotImage(glyph, progress: ticker.progress, ink: .black, template: true, badge: badge)
        case .count:
            return MenuGlyph.countImage(store.needsCount, ink: .black, template: true, badge: badge)
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
