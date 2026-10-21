import SwiftUI

/// The hero field, ported from kit.js `heroField`: a band of horizontal stripes across the canvas with a faint
/// gradient outside the disc, the disc itself, and the glide slot running in from the far left. The amber
/// touchdown dot sits at `t` along the slot. `t` is 1 at touchdown; `edge` is where the dot sits on the disc edge.
struct HeroField: View {
    var t: CGFloat
    /// Stripe count (kit.js `n`).
    var stripes = 11
    /// Opacity of the band outside the disc (kit.js `faint`).
    var faint: CGFloat = 0.07

    /// The `t` at which the dot is on the disc edge. The dot's path is 1.6 times the edge distance, as in kit.js.
    static let edge: CGFloat = 1 - 1 / 1.6

    /// Eased position of the dot: 2 s from the disc edge to touchdown, then 2 s back, on a 4 s loop.
    static func glide(_ date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
        let leg = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        let eased = 0.5 - 0.5 * cos(Double.pi * leg)
        return edge + (1 - edge) * CGFloat(eased)
    }

    var body: some View {
        Canvas { ctx, size in
            let W = size.width, D = size.height
            let n = CGFloat(stripes)
            let cx = W / 2, cy = D / 2, R = D / 2
            let pitch = 2 * R / n, h = pitch * 0.56, w = pitch * 1.35
            let ang: CGFloat = 24 * .pi / 180
            let ex = cx + R * 0.28, ey = cy + R * 0.30

            var bars = Path()
            for i in 0..<stripes {
                bars.addRect(CGRect(x: 0, y: pitch * (CGFloat(i) + 0.5) - h / 2, width: W, height: h))
            }

            // kit.js: translate(ex ey) rotate(ang), so the rotation applies first.
            let slot = Path(roundedRect: CGRect(x: -3000, y: -w / 2, width: 3000 + w / 2, height: w),
                            cornerRadius: w / 2)
                .applying(CGAffineTransform(rotationAngle: ang).concatenating(CGAffineTransform(translationX: ex, y: ey)))

            // Walk back from touchdown along the slot to the disc edge, then scale as kit.js does.
            let dx = -cos(ang), dy = -sin(ang)
            let fx = ex - cx, fy = ey - cy
            let b = fx * dx + fy * dy, c = fx * fx + fy * fy - R * R
            let s = (-b + (b * b - c).squareRoot()) * 1.6
            let px = ex + dx * s * (1 - t), py = ey + dy * s * (1 - t)

            let fade = Gradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(1 - faint), location: 0.3),
                .init(color: .black.opacity(1 - faint), location: 0.7),
                .init(color: .black, location: 1),
            ])
            let halo = R + pitch * 0.6

            // The band: stripes at the faint gradient, cut away around the disc and along the slot.
            ctx.drawLayer { layer in
                layer.fill(bars, with: .color(WinTheme.text))
                layer.blendMode = .destinationOut
                layer.fill(Path(CGRect(x: 0, y: 0, width: W, height: D)),
                           with: .linearGradient(fade, startPoint: .zero, endPoint: CGPoint(x: W, y: 0)))
                layer.fill(Path(ellipseIn: CGRect(x: cx - halo, y: cy - halo, width: 2 * halo, height: 2 * halo)),
                           with: .color(.black))
                layer.fill(slot, with: .color(.black))
            }

            // The disc: stripes inside the circle, with the slot cut out.
            ctx.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R)))
                layer.fill(bars, with: .color(WinTheme.text))
                layer.blendMode = .destinationOut
                layer.fill(slot, with: .color(.black))
            }

            ctx.fill(Path(ellipseIn: CGRect(x: px - w * 0.3, y: py - w * 0.3, width: w * 0.6, height: w * 0.6)),
                     with: .color(Color(hex: "FFB020")))
        }
    }
}
