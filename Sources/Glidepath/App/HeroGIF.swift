import SwiftUI
import AppKit
import ImageIO

/// The README hero: the running popover in dark mode, 6 s at 20 fps, looping forever. Time is injected, so every
/// render is the same. Frame i is at i / 20 s. One PR lands with changes at 2 s (frame 40) and one lands approved at
/// 4 s (frame 80). Written with ImageIO.
enum HeroGIF {
    static let frameCount = 120
    static let delay = 0.05
    /// 800 px wide for the README's 400 pt display; the popover is 360 pt wide.
    static let scale: CGFloat = 800 / 360
    /// Only the top 560 pt of the popover is kept, so tagline, install and the top of the hero fit one screen.
    static let heightPoints: CGFloat = 560
    static let landings: [(id: String, frame: Int, verdict: Verdict)] = [
        ("lumen/api#1113", 40, .changes),
        ("lumen/web#91", 80, .approve),
    ]

    /// The fixture at frame i, and the PRs that land on exactly this frame (the profile starts their slide here).
    static func frame(_ i: Int, now: Date) -> (Snapshot, Set<String>) {
        var snap = Fixtures.running(now)
        var landed: Set<String> = []
        for landing in landings where i >= landing.frame {
            let parts = landing.id.split(separator: "#")
            land(&snap, repo: String(parts[0]), number: Int(parts[1]) ?? 0, verdict: landing.verdict)
            if i == landing.frame { landed.insert(landing.id) }
        }
        return (snap, landed)
    }

    private static func land(_ snap: inout Snapshot, repo: String, number: Int, verdict: Verdict) {
        guard var run = snap.run,
              let ri = run.repos.firstIndex(where: { $0.slug == repo }),
              let pi = run.repos[ri].prs.firstIndex(where: { $0.n == number }) else { return }
        run.repos[ri].prs[pi].verdict = verdict
        run.repos[ri].prs[pi].active = false
        snap.run = run
    }

    @MainActor
    static func render(to path: String) -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let motion = ProfileMotion()
        var images: [CGImage] = []
        for i in 0..<frameCount {
            let (snap, landed) = frame(i, now: now)
            let store = Store(snapshot: snap, justLanded: landed, motion: motion)
            let view = PopoverView(store: store, offscreen: true)
                .environment(\.colorScheme, .dark)
                .background(Palette(.dark).ground)
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let full = renderer.cgImage,
                  let image = full.cropping(to: CGRect(x: 0, y: 0, width: full.width,
                                                       height: Int(heightPoints * scale))) else { return false }
            images.append(image)
        }
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                         "com.compuserve.gif" as CFString, images.count, nil) else {
            return false
        }
        let fileProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay]]
        for image in images {
            CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
        }
        return CGImageDestinationFinalize(dest)
    }
}
