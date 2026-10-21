import AppKit

/// The app icon (docs/design.md, section 9; design pass 3 wins). Artwork sits in the 824 pt rounded-rect grid
/// of a 1024 canvas. The full icon has depth: a vertical gradient ground, a top highlight, a drop shadow, a runway
/// in perspective, a glide slope and an amber touchdown light with a soft glow. Sizes of 64 pt and below use a
/// simplified drawing: the slope and the amber light only, with thicker strokes.
enum AppIcon {
    /// Draws the icon into `rect`. `simplified` picks the small-size drawing.
    static func draw(in rect: NSRect, simplified: Bool = false) {
        let s = rect.width / 1024
        // Design space: 1024 points, origin top left. Maps into `rect`.
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * s, y: rect.maxY - y * s)
        }
        let artwork = NSRect(x: rect.minX + 100 * s, y: rect.minY + 100 * s, width: 824 * s, height: 824 * s)
        let body = NSBezierPath(roundedRect: artwork, xRadius: 185 * s, yRadius: 185 * s)

        if simplified {
            ground(body, artwork)
            slope(p, width: 123 * s, from: (232, 232), to: (560, 650))
            light(p, centre: (566, 700), radius: 120 * s, glow: false)
            return
        }

        // Drop shadow 0/12/24 black 35%, cast by the body.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
        shadow.shadowBlurRadius = 24 * s
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.set()
        NSColor(hex: "16395A").setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()

        ground(body, artwork)

        // 1 pt inner highlight along the top edge, at white 20%.
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSColor.white.withAlphaComponent(0.20).setFill()
        NSRect(x: artwork.minX, y: artwork.maxY - 2 * s, width: artwork.width, height: 2 * s).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        runway(p, s)
        slope(p, width: 34 * s * 1024 / 1024, from: (250, 250), to: (528, 660))
        light(p, centre: (560, 790), radius: 32 * s, glow: true, glowRadius: 60 * s)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Vertical gradient ground, #16395A at the top to #091827 at the bottom.
    private static func ground(_ body: NSBezierPath, _ artwork: NSRect) {
        NSGradient(starting: NSColor(hex: "091827"), ending: NSColor(hex: "16395A"))?
            .draw(in: body, angle: 90)
    }

    /// The runway in perspective along the lower third: a trapezoid, a white dashed centreline and two rows of
    /// edge lights.
    private static func runway(_ p: (CGFloat, CGFloat) -> NSPoint, _ s: CGFloat) {
        let trapezoid = NSBezierPath()
        trapezoid.move(to: p(442, 640))
        trapezoid.line(to: p(582, 640))
        trapezoid.line(to: p(812, 924))
        trapezoid.line(to: p(212, 924))
        trapezoid.close()
        NSColor(hex: "0B2135").setFill()
        trapezoid.fill()

        // Centreline dashes.
        NSColor.white.withAlphaComponent(0.85).setFill()
        var y: CGFloat = 660
        while y < 920 {
            let dash = NSBezierPath()
            dash.move(to: p(512, y))
            dash.line(to: p(512, min(y + 22, 920)))
            dash.lineWidth = 6 * s
            dash.lineCapStyle = .butt
            NSColor.white.withAlphaComponent(0.85).setStroke()
            dash.stroke()
            y += 42
        }

        // Two rows of tiny edge lights, on each side.
        for t in stride(from: CGFloat(0.12), through: 0.96, by: 0.12) {
            let yy = 660 + t * (924 - 660)
            let half = 70 + (yy - 640) / (924 - 640) * (300 - 70)
            for side: CGFloat in [-1, 1] {
                for inset: CGFloat in [0, 16] {
                    let x = 512 + side * (half - inset)
                    let dot = NSRect(x: p(x, yy).x - 3 * s, y: p(x, yy).y - 3 * s, width: 6 * s, height: 6 * s)
                    NSColor.white.withAlphaComponent(0.8).setFill()
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
        }
    }

    /// The glide slope: a round-capped line from the upper left toward the threshold.
    private static func slope(_ p: (CGFloat, CGFloat) -> NSPoint, width: CGFloat,
                              from a: (CGFloat, CGFloat), to b: (CGFloat, CGFloat)) {
        let line = NSBezierPath()
        line.move(to: p(a.0, a.1))
        line.line(to: p(b.0, b.1))
        line.lineWidth = width
        line.lineCapStyle = .round
        NSColor(hex: "4DA3FF").setStroke()
        line.stroke()
    }

    /// The amber touchdown light, with a soft glow of 35% amber.
    private static func light(_ p: (CGFloat, CGFloat) -> NSPoint, centre: (CGFloat, CGFloat), radius: CGFloat,
                              glow: Bool, glowRadius: CGFloat = 0) {
        let c = p(centre.0, centre.1)
        if glow {
            let amber = NSColor(hex: "FFB020")
            NSGradient(starting: amber.withAlphaComponent(0.35), ending: amber.withAlphaComponent(0))?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: glowRadius, options: [])
        }
        NSColor(hex: "FFB020").setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    /// The icon as a PNG at `pixels` square. Sizes of 64 and below get the simplified drawing.
    static func png(pixels: Int) -> Data? {
        let size = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, simplified: pixels <= 64)
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
