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
    static func image(_ state: GlyphState, progress: Double, ink: NSColor, template: Bool) -> NSImage {
        let count: Int? = {
            switch state {
            case .running(let n), .changesWaiting(let n): return n
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

struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @StateObject private var ticker = SweepTicker()

    var body: some View {
        let glyph = store.glyph
        Image(nsImage: MenuGlyph.image(glyph, progress: ticker.progress, ink: .black, template: true))
            .onAppear { ticker.setRunning(store.snap.running) }
            .onChange(of: store.snap.running) { _, running in ticker.setRunning(running) }
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
