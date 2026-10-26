import SwiftUI
import AppKit

/// Every kit component in every state, for review against the prototype shots. Not part of the running app.
///
///     glidepath --kit-gallery            opens the pages as windows and stays open
///     glidepath --kit-gallery <dir>      writes one PNG per page (and the menu bar glyphs) into <dir>, then exits
///     glidepath --kit-gallery idle       one quiet header, for measuring idle CPU
///
/// Set GLIDEPATH_FORCE_FALLBACK_GLASS=1 to draw the macOS 14–15 materials; PNGs then end in "-fallback".
/// Pages are real windows, so Liquid Glass renders as on screen; the PNGs hold the window alone (see `capture`).
@MainActor
enum KitGallery {
    struct Page {
        let name: String
        let width: CGFloat
        var padding: CGFloat = 28
        let view: AnyView
    }

    private static var windows: [NSWindow] = []

    static func run(_ arg: String?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let pages = arg == "idle" ? [idle] : all
        app.activate(ignoringOtherApps: true)
        guard let dir = arg, dir != "idle" else {
            for (i, page) in pages.enumerated() { show(page, index: i) }
            app.run()
            exit(0)
        }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suffix = KitGlass.forceFallback ? "-fallback" : ""
        // One page on screen at a time, so the pages never overlap.
        func next(_ i: Int) {
            guard i < pages.count else {
                if !KitGlass.forceFallback { writeGlyphs(to: out.appendingPathComponent("menu-bar-glyphs.png")) }
                exit(0)
            }
            let window = show(pages[i], index: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                capture(window, to: out.appendingPathComponent("\(pages[i].name)\(suffix).png"))
                window.orderOut(nil)
                next(i + 1)
            }
        }
        next(0)
        app.run()
        exit(0)
    }

    // MARK: Pages

    static var states: [(String, GlideState)] {
        let now = Date()
        let five = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
            .addingTimeInterval(9 * 3600)
        return [
            ("Quiet", .quiet(next: five)),
            ("Checking", .checking(CheckProgress(done: 2, total: 5, repo: "lumen/web"))),
            ("Needs you", .needs(count: 4)),
            ("Problem", .problem(reason: .signedOut, fix: .signIn)),
            ("Paused", .paused(until: tomorrow)),
            ("Holding back", .holdingBack(reason: .usageReserve(reserve: 20), resumesAt: now.addingTimeInterval(7200))),
        ]
    }

    static var all: [Page] { [statusHeaders, popoverHeaders, holdButtons, undoBanner] + popovers }

    /// The menu bar popover in every state, from fixtures. The real popover's glass is drawn by the system; here the
    /// smoked window stands in for it.
    static var popovers: [Page] {
        states.map { name, shown in
            var state = shown
            var needs: [Need] = []
            var since = ""
            switch state {
            case .needs:
                needs = sampleNeeds
                state = .needs(count: needs.count)
            case .checking: needs = Array(sampleNeeds.prefix(2))
            case .quiet, .holdingBack: since = "Posted 4 reviews, pushed a fix to #1253, merged #1246"
            default: break
            }
            if case .paused = state { needs = Array(sampleNeeds.prefix(1)) }
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            return Page(name: "popover-\(slug)", width: PopoverContent.width, padding: 0, view: AnyView(
                PopoverContent(state: state, needs: needs, since: since, autopilot: false,
                               paused: { if case .paused = state { return true }; return false }(), act: { _ in })))
        }
    }

    /// Five Needs-you items, so the needs page shows four rows and "and 1 more".
    static var sampleNeeds: [Need] {
        func need(_ kind: NeedKind, _ repo: String, _ n: Int, _ title: String, _ author: String?) -> Need {
            Need(id: "\(repo)#\(n)", kind: kind, repo: repo, number: n, title: title, author: author, reason: "",
                 action: .post, outward: true, since: nil)
        }
        // Logins GitHub cannot have, so the rows show initials and no real person's picture.
        return [
            need(.reviewReady(.changes), "lumen/web", 1276, "Selection race in the upload picker", "ellie_"),
            need(.fixReady, "lumen/api", 1253, "Export certifications as CSV", nil),
            need(.readyToMerge, "lumen/api", 1301, "Notification schema: migration and backfill", nil),
            need(.replyReady(to: "gadi"), "lumen/web", 1250, "Keyboard focus in the upload picker", nil),
            need(.reviewReady(.approve), "lumen/web", 1290, "Bump the image library", "dana_"),
        ]
    }

    /// The window header in every state: title, sentence, control, the line at full size.
    static var statusHeaders: Page {
        Page(name: "status-header", width: 760, view: AnyView(VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                caption(s.0)
                StatusHeader("Inbox", state: s.1, onFix: {}) {
                    Button(Copy.statusButton(s.1)) {}.glassButtonStyle()
                }
            }
        }))
    }

    /// The popover's top in every state: the line on top, the sentence as the title.
    static var popoverHeaders: Page {
        Page(name: "popover-header", width: 380, view: AnyView(VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                caption(s.0)
                StatusHeader(state: s.1, size: .popover, onFix: {}) {
                    Button(Copy.statusButton(s.1)) {}.glassButtonStyle()
                }
            }
        }))
    }

    static var holdButtons: Page {
        Page(name: "hold-button", width: 760, view: AnyView(HoldGallery()))
    }

    static var undoBanner: Page {
        Page(name: "undo-banner", width: 760, view: AnyView(UndoGallery()))
    }

    static var idle: Page {
        Page(name: "idle", width: 760, view: AnyView(VStack(alignment: .leading, spacing: 30) {
            StatusHeader("Inbox", state: states[0].1, onFix: {}) {
                Button(Copy.checkNow) {}.glassButtonStyle()
            }
            StatusHeader(state: states[0].1, size: .popover, onFix: {}) {
                Button(Copy.checkNow) {}.glassButtonStyle()
            }
            .frame(width: 340)
        }))
    }

    static func caption(_ text: String) -> some View {
        Text(text).font(Ladder.fine).foregroundStyle(.tertiary)
    }

    // MARK: Windows

    @discardableResult
    private static func show(_ page: Page, index: Int) -> NSWindow {
        let root = page.view
            .padding(page.padding)
            .frame(width: page.width, alignment: .topLeading)
            .background(SmokedGlass())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .preferredColorScheme(.dark)
            .tint(.graphite)
        let host = NSHostingView(rootView: root)
        let size = host.fittingSize
        let w = KeyWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.appearance = NSAppearance(named: .darkAqua)
        w.title = page.name
        w.contentView = host
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        w.setFrameTopLeftPoint(NSPoint(x: screen.minX + 60 + CGFloat(index) * 40, y: screen.maxY - 40 - CGFloat(index) * 30))
        w.makeKeyAndOrderFront(nil)
        windows.append(w)
        return w
    }

    /// The window alone, at 1x: never what is behind it, so no other app's content ends up in a PNG. Behind-window blur
    /// shows as its plain material tone.
    private static func capture(_ window: NSWindow, to url: URL) {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(sym, to: Create.self)
        window.orderFrontRegardless()
        // kCGWindowListOptionIncludingWindow = 8; kCGWindowImageBoundsIgnoreFraming = 1
        guard let image = create(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue(),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(window.frame.width),
                                         pixelsHigh: Int(window.frame.height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            print("capture failed: \(url.lastPathComponent)")
            return
        }
        // Scaled to points whatever the display's scale, so the PNGs stay small.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: .zero).draw(in: NSRect(origin: .zero, size: window.frame.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }

    /// The menu bar glyphs on a dark and a light bar, at 3x so the shapes read.
    private static func writeGlyphs(to url: URL) {
        let cell = CGSize(width: 74, height: 30), scale: CGFloat = 3
        let rows: [(NSColor, NSColor)] = [(NSColor(white: 0.13, alpha: 1), .white), (NSColor(white: 0.93, alpha: 1), .black)]
        let size = CGSize(width: cell.width * CGFloat(states.count), height: cell.height * CGFloat(rows.count) + 16)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.2, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (r, (ground, ink)) in rows.enumerated() {
            let y = 16 + CGFloat(rows.count - 1 - r) * cell.height
            ground.setFill()
            NSRect(x: 0, y: y, width: size.width, height: cell.height).fill()
            for (i, s) in states.enumerated() {
                let glyph = GlideGlyph.image(for: s.1, phase: 0.45)
                let tinted = NSImage(size: glyph.size, flipped: false) { rect in
                    glyph.draw(in: rect)
                    ink.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                let count: NSString? = { if case .needs(let n) = s.1 { return "\(n)" as NSString }; return nil }()
                let w = glyph.size.width + (count == nil ? 0 : 10)
                let x = CGFloat(i) * cell.width + (cell.width - w) / 2
                tinted.draw(in: NSRect(x: x, y: y + 7, width: glyph.size.width, height: glyph.size.height))
                count?.draw(at: NSPoint(x: x + glyph.size.width + 2, y: y + 7),
                            withAttributes: [.font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: ink])
            }
        }
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor(white: 1, alpha: 0.6)]
        for (i, s) in states.enumerated() {
            let text = s.0 as NSString
            text.draw(at: NSPoint(x: CGFloat(i) * cell.width + (cell.width - text.size(withAttributes: label).width) / 2, y: 3),
                      withAttributes: label)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}

/// Borderless, but key like a normal window, so controls draw active.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Hold buttons at rest, mid-hold filling their pane, held to full, after a tap (hint and shake), and disabled.
private struct HoldGallery: View {
    @StateObject private var tapped = HoldModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KitGallery.caption("At rest · mid-hold, the light fills the pane · held to full · tapped · disabled")
            GlassGroup(spacing: 10) {
                VStack(spacing: 10) {
                    row("Selection race in the upload picker", need: "Review ready to post", ref: "lumen/web #1276", fill: 0) {
                        HoldButton("Post review", hint: "Hold to post") {}
                    }
                    row("Export certifications as CSV", need: "Fix ready to push", ref: "lumen/api #1253", fill: 0.55) {
                        HoldButton("Push fix", hint: "Hold to push", model: HoldModel()) {}
                    }
                    row("Notification schema: migration and backfill", need: "Ready to merge", ref: "lumen/api #1301", fill: 0) {
                        HoldButton("Merge", hint: "Hold to merge", held: true) {}
                    }
                    row("Keyboard focus in the upload picker", need: "Reply ready", ref: "lumen/web #1250", fill: 0) {
                        HoldButton("Send reply", hint: "Hold to send", model: tapped) {}
                    }
                    row("Bump the image library", need: "Review ready to post", ref: "lumen/web #1290", fill: 0) {
                        HoldButton("Post review", hint: "Hold to post") {}.disabled(true)
                    }
                }
            }
        }
        .onAppear {
            tapped.press {}
            tapped.release()
        }
    }

    private func row<B: View>(_ title: String, need: String, ref: String, fill: CGFloat,
                              @ViewBuilder button: () -> B) -> some View {
        HStack(spacing: 14) {
            Circle().fill(Color.gray.gradient).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Ladder.rowTitle)
                Text("\(Text(need).foregroundStyle(Color.amber))  ·  \(ref)")
                    .font(Ladder.secondary).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            button()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LightFill(progress: fill))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassPane(tint: .black.opacity(0.3), interactive: true)
    }
}

/// The undo banner as it shows after a discard.
private struct UndoGallery: View {
    @StateObject private var center = UndoCenter()

    var body: some View {
        VStack(spacing: 0) {
            KitGallery.caption("After Discard: 8 seconds, Undo or ⌘Z").frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 90)
            UndoBanner(center: center)
        }
        .frame(height: 170)
        .onAppear { center.show("Review discarded.", undoManager: nil, undo: {}) }
    }
}
