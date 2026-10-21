import SwiftUI
import AppKit

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
        Group {
            if !store.snap.jobInstalled {
                Image(systemName: "exclamationmark.triangle")
            } else if store.snap.running {
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarIcon.make(angle: ticker.angle, sweeping: true))
                    Text("\(store.done)/\(store.strips.count)")
                        .monospacedDigit()
                }
            } else {
                Image(nsImage: MenuBarIcon.make(angle: 0, sweeping: false))
            }
        }
        .onAppear { ticker.setRunning(store.snap.running) }
        .onChange(of: store.snap.running) { _, running in ticker.setRunning(running) }
    }
}

enum MenuBarIcon {
    /// 18x18 template: ring, center dot, and (while running) a sweep line at `angle` degrees.
    static func make(angle: Double, sweeping: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let center = NSPoint(x: 9, y: 9)
            let ringRadius: CGFloat = 7
            let ring = NSBezierPath(ovalIn: NSRect(x: 9 - ringRadius, y: 9 - ringRadius,
                                                   width: ringRadius * 2, height: ringRadius * 2))
            ring.lineWidth = 1.5
            ring.stroke()

            if sweeping {
                let rad = angle * .pi / 180
                let sweep = NSBezierPath()
                sweep.move(to: center)
                sweep.line(to: NSPoint(x: center.x + ringRadius * CGFloat(cos(rad)),
                                       y: center.y + ringRadius * CGFloat(sin(rad))))
                sweep.lineWidth = 1.5
                sweep.lineCapStyle = .round
                sweep.stroke()
            }

            NSBezierPath(ovalIn: NSRect(x: 7.5, y: 7.5, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
