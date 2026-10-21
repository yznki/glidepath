import SwiftUI

/// The Glidepath mark, as kit.js draws it: a disc of horizontal stripes with a glide slot cut in from the
/// upper left at 24 degrees. The slot ends at the touchdown dot (amber). `t` moves the dot along the slot
/// (1 = touchdown); `n` is the stripe count.
struct GlidepathMark: View {
    var size: CGFloat
    var t: CGFloat = 1
    var n: Int = 7

    var body: some View {
        Canvas { ctx, canvas in
            // Geometry in the mockup's 512 space, mapped to the canvas by one transform.
            let cx: CGFloat = 512, cy: CGFloat = 512
            let R: CGFloat = 512 * 0.62
            let pitch = 2 * R / CGFloat(n), h = pitch * 0.56, w = pitch * 1.35
            let ang: CGFloat = 24 * .pi / 180
            let ex = cx + R * 0.28, ey = cy + R * 0.30
            let k = canvas.width / (2 * R + 8)
            ctx.concatenate(CGAffineTransform(translationX: -(cx - R - 4), y: -(cy - R - 4)).scaledBy(x: k, y: k))

            // The slot: a rounded bar from far left to the touchdown point, rotated 24 degrees about it.
            let slotLocal = CGRect(x: -2000, y: -w / 2, width: 2000 + w / 2, height: w)
            let slot = Path(roundedRect: slotLocal, cornerRadius: w / 2)
                .applying(CGAffineTransform(translationX: ex, y: ey).rotated(by: ang))

            ctx.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R)))
                for i in 0..<n {
                    let y = cy - R + pitch * (CGFloat(i) + 0.5) - h / 2
                    layer.fill(Path(CGRect(x: cx - R, y: y, width: 2 * R, height: h)), with: .color(WinTheme.text))
                }
                layer.blendMode = .destinationOut
                layer.fill(slot, with: .color(.black))
            }

            // The touchdown dot: walk back from T along the slot direction to the disc edge, then travel t of that.
            let dx = -cos(ang), dy = -sin(ang)
            let fx = ex - cx, fy = ey - cy
            let b = fx * dx + fy * dy, c = fx * fx + fy * fy - R * R
            let s = -b + (b * b - c).squareRoot()
            let px = ex + dx * s * (1 - t), py = ey + dy * s * (1 - t)
            let dot = CGRect(x: px - w * 0.3, y: py - w * 0.3, width: w * 0.6, height: w * 0.6)
            ctx.fill(Path(ellipseIn: dot), with: .color(Color(hex: "FFB020")))
        }
        .frame(width: size, height: size)
    }
}
