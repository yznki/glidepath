// Draws the Glidepath app icon (1024x1024 PNG). Usage: xcrun swift icon.swift <out.png>
import AppKit

func hex(_ s: String, _ a: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let c = NSPoint(x: 512, y: 512)
let teal = hex("#2BB3A3")

// Squircle body.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
body.addClip()
NSGradient(starting: hex("#0E1A1F"), ending: hex("#08262A"))!.draw(in: body.bounds, angle: -90)

// Rings, decreasing alpha.
for (r, a) in [(330.0, 0.55), (230.0, 0.35), (130.0, 0.2)] as [(CGFloat, CGFloat)] {
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ring.lineWidth = 14
    teal.withAlphaComponent(a).setStroke()
    ring.stroke()
}

// Sweep wedge: 1-degree slices, alpha ramps up toward the leading edge at 45 degrees.
let lead: CGFloat = 45
for k in 0..<40 {
    let a0 = (lead - 40 + CGFloat(k)) * .pi / 180
    let a1 = (lead - 40 + CGFloat(k) + 1.2) * .pi / 180
    let slice = NSBezierPath()
    slice.move(to: c)
    slice.line(to: NSPoint(x: c.x + 340 * cos(a0), y: c.y + 340 * sin(a0)))
    slice.line(to: NSPoint(x: c.x + 340 * cos(a1), y: c.y + 340 * sin(a1)))
    slice.close()
    teal.withAlphaComponent(0.5 * CGFloat(k + 1) / 40).setFill()
    slice.fill()
}
let leadLine = NSBezierPath()
leadLine.move(to: c)
leadLine.line(to: NSPoint(x: c.x + 340 * cos(lead * .pi / 180), y: c.y + 340 * sin(lead * .pi / 180)))
leadLine.lineWidth = 10
teal.setStroke()
leadLine.stroke()

// Blips: one amber hold, two green approvals.
let blips: [(CGFloat, CGFloat, NSColor)] = [
    (100, 230, hex("#E5A000")),
    (200, 150, hex("#30A46C")),
    (300, 280, hex("#30A46C")),
]
for (angle, r, color) in blips {
    let p = NSPoint(x: c.x + r * cos(angle * .pi / 180), y: c.y + r * sin(angle * .pi / 180))
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color
    glow.shadowBlurRadius = 30
    glow.shadowOffset = .zero
    glow.set()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: p.x - 34, y: p.y - 34, width: 68, height: 68)).fill()
    NSGraphicsContext.restoreGraphicsState()
}
NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
