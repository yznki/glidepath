import AppKit
import ScreenCaptureKit
// Prototype screenshots. Composites one prototype window over the wallpaper only, never other apps,
// so the translucent glass reads as it does on screen.
// Usage: cap send <debug-command>          posts a command to the running prototype
//        cap shot <out.png> <title|popover>  captures the window whose title contains the text
let a = CommandLine.arguments
if a[1] == "send" {
    DistributedNotificationCenter.default().postNotificationName(.init("glidepath.proto"), object: a[2], userInfo: nil, deliverImmediately: true)
    RunLoop.current.run(until: .now + 0.08)
    exit(0)
}
let out = a[2]
let want = a[3]
guard let pid = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.glidepath.prototype.v2" })?.processIdentifier else { print("prototype not running"); exit(1) }
let sem = DispatchSemaphore(value: 0)
Task { do {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let mine = content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.height > 60 }
    guard let target = mine.first(where: { want == "popover" ? $0.windowLayer > 0 : ($0.title ?? "").contains(want) && $0.windowLayer == 0 }) else { print("no window"); exit(1) }
    let wall = content.windows.filter { $0.title == "Wallpaper" || $0.title == "Display 1 Backstop" }
        + content.windows.filter { $0.owningApplication?.processID == pid && $0.title == "Backdrop" }
    let display = content.displays.first { $0.frame.intersects(target.frame) } ?? content.displays[0]
    let filter = SCContentFilter(display: display, including: wall + [target])
    let cfg = SCStreamConfiguration()
    let pad: CGFloat = want == "popover" ? 30 : 36
    let r = target.frame.insetBy(dx: -pad, dy: -pad)
    cfg.sourceRect = CGRect(x: r.minX - display.frame.minX, y: r.minY - display.frame.minY, width: r.width, height: r.height)
    let scale = CGFloat(filter.pointPixelScale)
    cfg.width = Int(r.width * scale); cfg.height = Int(r.height * scale)
    cfg.showsCursor = false
    cfg.captureResolution = .best
    let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("saved", out)
    sem.signal()
} catch { print(error); exit(1) } }
sem.wait()
