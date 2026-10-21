import AppKit

/// The app icon (docs/design.md, section 9), drawn in code so the icon file, the snapshot and the menu bar
/// all come from one place. A night-blue squircle, a glide slope in blue descending to a runway of white
/// dashes, and one amber square landed on the runway. Legible at 16 pt.
enum AppIcon {
    static func draw(in rect: NSRect) {
        let s = rect.width
        let origin = rect.origin
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: origin.x + x * s, y: origin.y + (1 - y) * s)
        }
        let body = NSBezierPath(roundedRect: rect, xRadius: s * 0.2237, yRadius: s * 0.2237)
        NSColor(hex: "0E2236").setFill()
        body.fill()

        let slope = NSBezierPath()
        slope.move(to: p(0.20, 0.26))
        slope.line(to: p(0.60, 0.60))
        slope.lineWidth = s * 0.085
        slope.lineCapStyle = .round
        NSColor(hex: "4DA3FF").setStroke()
        slope.stroke()

        NSColor.white.withAlphaComponent(0.92).setFill()
        for k in 0..<3 {
            let x = 0.60 + CGFloat(k) * 0.12
            let dash = NSRect(x: origin.x + x * s, y: origin.y + (1 - 0.72 - 0.02) * s,
                              width: 0.09 * s, height: 0.06 * s)
            NSBezierPath(roundedRect: dash, xRadius: s * 0.01, yRadius: s * 0.01).fill()
        }

        NSColor(hex: "E5A000").setFill()
        let landed = NSRect(x: origin.x + 0.64 * s, y: origin.y + (1 - 0.68) * s, width: 0.15 * s, height: 0.15 * s)
        NSBezierPath(roundedRect: landed, xRadius: s * 0.02, yRadius: s * 0.02).fill()
    }

    /// The icon as a PNG at `pixels` square.
    static func png(pixels: Int) -> Data? {
        let size = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
