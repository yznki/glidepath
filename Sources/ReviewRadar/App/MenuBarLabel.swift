import SwiftUI
import AppKit

/// The menu bar glyph states (docs/design.md, menu bar table).
enum GlyphState: Equatable {
    case idle
    case running(active: Int)
    case changesWaiting
    case paused
    case failed
}

/// Draws the glyph at 18 pt. The sweep arm angle is passed in, so the live app and snapshots share one drawing.
enum MenuGlyph {
    static func image(_ state: GlyphState, angle: Double, ink: NSColor, template: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            ink.set()
            let c = NSPoint(x: 9, y: 9)
            // The failed glyph is a triangle on its own; every other state is the ring.
            if state != .failed {
                let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 14))
                ring.lineWidth = 1.5
                ring.stroke()
            }

            switch state {
            case .idle, .changesWaiting:
                NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
                if state == .changesWaiting {
                    NSColor(red: 0xE5 / 255, green: 0xA0 / 255, blue: 0, alpha: 1).set()
                    NSBezierPath(ovalIn: NSRect(x: 11.7, y: 11.7, width: 5.6, height: 5.6)).fill()
                    ink.set()
                }
            case .running:
                let rad = angle * .pi / 180
                let arm = NSBezierPath()
                arm.move(to: c)
                arm.line(to: NSPoint(x: c.x + 7 * CGFloat(cos(rad)), y: c.y + 7 * CGFloat(sin(rad))))
                arm.lineWidth = 1.5
                arm.lineCapStyle = .round
                arm.stroke()
                NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            case .paused:
                NSBezierPath(rect: NSRect(x: 7.2, y: 6, width: 1.6, height: 6)).fill()
                NSBezierPath(rect: NSRect(x: 9.6, y: 6, width: 1.6, height: 6)).fill()
            case .failed:
                let tri = NSBezierPath()
                tri.move(to: NSPoint(x: 9, y: 2.5))
                tri.line(to: NSPoint(x: 16.5, y: 15.5))
                tri.line(to: NSPoint(x: 1.5, y: 15.5))
                tri.close()
                tri.lineWidth = 1.5
                tri.stroke()
                NSBezierPath(rect: NSRect(x: 8.25, y: 6.5, width: 1.5, height: 5)).fill()
                NSBezierPath(ovalIn: NSRect(x: 8.2, y: 12.4, width: 1.6, height: 1.6)).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}

/// Drives the sweep angle at 10 fps. The timer exists only while a run is in progress.
@MainActor
final class SweepTicker: ObservableObject {
    @Published var angle: Double = 0
    private var timer: Timer?

    func setRunning(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.angle = (self.angle + 36).truncatingRemainder(dividingBy: 360)
            }
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @StateObject private var ticker = SweepTicker()

    var body: some View {
        let glyph = store.glyph
        Group {
            if case .running(let active) = glyph {
                HStack(spacing: 4) {
                    Image(nsImage: MenuGlyph.image(glyph, angle: ticker.angle, ink: .black, template: true))
                    Text("\(active)").monospacedDigit()
                }
            } else {
                Image(nsImage: MenuGlyph.image(glyph, angle: 0, ink: glyph == .changesWaiting ? .labelColor : .black,
                                               template: glyph != .changesWaiting))
            }
        }
        .onAppear { ticker.setRunning(store.snap.running) }
        .onChange(of: store.snap.running) { _, running in ticker.setRunning(running) }
    }
}
