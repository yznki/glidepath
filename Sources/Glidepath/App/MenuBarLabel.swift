import SwiftUI
import AppKit

/// The menu bar glyph states (docs/design.md, section 8). Everything is a template image: no colour.
enum GlyphState: Equatable {
    case idle
    case running(active: Int)
    case changesWaiting(count: Int)
    case paused
    case failed
}

/// Draws the glyph family. The base mark is a 14 pt slope descending left to right onto a 6 pt runway, on an 18 pt
/// canvas, with 1.75 pt round-cap strokes. Counts are 12 pt semibold, the same in every state.
enum MenuGlyph {
    static let canvas: CGFloat = 18
    static let stroke: CGFloat = 1.75
    static let countFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// The glyph in `ink`. `template` marks it for the menu bar; snapshots pass false so the ink shows.
    static func image(_ state: GlyphState, progress: Double, ink: NSColor, template: Bool) -> NSImage {
        if state == .failed {
            return triangle(ink: ink, template: template)
        }
        let count: Int? = {
            switch state {
            case .running(let n), .changesWaiting(let n): return n
            default: return nil
            }
        }()
        let label = count.map { NSAttributedString(string: "\($0)", attributes: [.font: countFont, .foregroundColor: ink]) }
        let width = canvas + (label.map { $0.size().width + 3 } ?? 0)
        let image = NSImage(size: NSSize(width: width, height: canvas), flipped: false) { _ in
            ink.set()
            if state == .paused {
                pauseBars()
                runway()
            } else {
                slope()
                runway()
            }
            if case .running = state {
                dot(progress: progress)
            }
            label?.draw(at: NSPoint(x: canvas + 3, y: (canvas - label!.size().height) / 2 - 0.5))
            return true
        }
        image.isTemplate = template
        return image
    }

    /// The slope from the top left to the runway's start. Its end is at (11.5, 4.5), where the runway begins.
    private static let slopeStart = NSPoint(x: 1.5, y: 14.5)
    private static let slopeEnd = NSPoint(x: 11.5, y: 4.5)

    private static func slope() {
        let line = NSBezierPath()
        line.move(to: slopeStart)
        line.line(to: slopeEnd)
        line.lineWidth = stroke
        line.lineCapStyle = .round
        line.stroke()
    }

    private static func runway() {
        let bar = NSBezierPath()
        bar.move(to: slopeEnd)
        bar.line(to: NSPoint(x: slopeEnd.x + 6, y: slopeEnd.y))
        bar.lineWidth = stroke
        bar.lineCapStyle = .round
        bar.stroke()
    }

    /// Paused: two pause bars where the slope was.
    private static func pauseBars() {
        for x: CGFloat in [4.5, 8.5] {
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: x, y: 6))
            bar.line(to: NSPoint(x: x, y: 13))
            bar.lineWidth = stroke
            bar.lineCapStyle = .round
            bar.stroke()
        }
    }

    /// A 3 pt dot moving down the slope as `progress` (0 to 1) advances.
    private static func dot(progress: Double) {
        let f = CGFloat(progress - floor(progress))
        let x = slopeStart.x + (slopeEnd.x - slopeStart.x) * f
        let y = slopeStart.y + (slopeEnd.y - slopeStart.y) * f
        NSBezierPath(ovalIn: NSRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)).fill()
    }

    /// The failed state: the system's outline warning symbol, nothing else.
    private static func triangle(ink: NSColor, template: Bool) -> NSImage {
        guard let symbol = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) else {
            return NSImage(size: NSSize(width: canvas, height: canvas))
        }
        let size = symbol.size
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
            let target = NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                width: size.width, height: size.height)
            symbol.draw(in: target)
            ink.set()
            target.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = template
        return image
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
