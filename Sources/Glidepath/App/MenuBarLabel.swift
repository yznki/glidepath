import SwiftUI
import AppKit

/// The menu bar glyph states (docs/design.md, section 8).
enum GlyphState: Equatable {
    case idle
    case running(active: Int)
    case changesWaiting(count: Int)
    case paused
    case failed
}

/// Draws the 18 pt glyph: a short descending slope ending on a runway bar. `progress` (0...1) places the
/// moving dot while running. Every state but changes-waiting is a template image.
enum MenuGlyph {
    static func image(_ state: GlyphState, progress: Double, ink: NSColor, count: NSColor, template: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            ink.set()
            switch state {
            case .failed:
                let tri = NSBezierPath()
                tri.move(to: NSPoint(x: 9, y: 2.5))
                tri.line(to: NSPoint(x: 16.5, y: 15.5))
                tri.line(to: NSPoint(x: 1.5, y: 15.5))
                tri.close()
                tri.lineWidth = 1.5
                tri.lineJoinStyle = .round
                tri.stroke()
                NSBezierPath(rect: NSRect(x: 8.25, y: 6.5, width: 1.5, height: 5)).fill()
                NSBezierPath(ovalIn: NSRect(x: 8.2, y: 12.4, width: 1.6, height: 1.6)).fill()
                return true
            case .paused:
                NSBezierPath(rect: NSRect(x: 4.5, y: 5, width: 2, height: 8)).fill()
                NSBezierPath(rect: NSRect(x: 8.5, y: 5, width: 2, height: 8)).fill()
            default:
                slope()
            }
            runway()
            switch state {
            case .running:
                let f = CGFloat(progress - floor(progress))
                let x = 2 + 9 * f, y = 13.5 - 8 * f
                NSBezierPath(ovalIn: NSRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)).fill()
            case .changesWaiting(let n):
                let text = NSAttributedString(string: "\(n)", attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: count,
                ])
                text.draw(at: NSPoint(x: 12.5, y: 9.5))
            default:
                break
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    /// A slope descending from the top left to the bottom right, where the runway is.
    private static func slope() {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 2, y: 13.5))
        line.line(to: NSPoint(x: 11, y: 5.5))
        line.lineWidth = 1.5
        line.lineCapStyle = .round
        line.stroke()
    }

    private static func runway() {
        NSBezierPath(roundedRect: NSRect(x: 11, y: 3.5, width: 6, height: 2), xRadius: 0.5, yRadius: 0.5).fill()
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let glyph = store.glyph
        Group {
            switch glyph {
            case .running(let active):
                HStack(spacing: 4) {
                    Image(nsImage: MenuGlyph.image(glyph, progress: ticker.progress, ink: .black,
                                                   count: .black, template: true))
                    Text("\(active)").monospacedDigit()
                }
            case .changesWaiting:
                Image(nsImage: MenuGlyph.image(glyph, progress: 0, ink: .labelColor,
                                               count: scheme == .dark ? NSColor(hex: "FFB000") : NSColor(hex: "C77700"),
                                               template: false))
            default:
                Image(nsImage: MenuGlyph.image(glyph, progress: 0, ink: .black, count: .black, template: true))
            }
        }
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
