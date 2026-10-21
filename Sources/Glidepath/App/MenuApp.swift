import SwiftUI
import AppKit

/// The menu bar app. Same binary as the CLI: `glidepath` with no arguments (or `app`) lands here.
struct GlidepathApp: App {
    init() {
        let args = CommandLine.arguments
        // Snapshot rendering: draw the fixtures to PNGs, then exit before any UI starts.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let outDir = args[i + 1]
            MainActor.assumeIsolated { Snapshotter.run(outDir: outDir) }
            exit(0)
        }
        // README hero: the running popover as a looping GIF, with injected time.
        if let i = args.firstIndex(of: "--hero-gif"), i + 1 < args.count {
            let path = args[i + 1]
            let ok = MainActor.assumeIsolated { HeroGIF.render(to: path) }
            print(ok ? "wrote \(path)" : "hero gif failed: \(path)")
            exit(ok ? 0 : 1)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: Store.shared)
        } label: {
            MenuBarLabel(store: Store.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders the design states from fixtures into docs/shots. Not used by the running app.
@MainActor
enum Snapshotter {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let states: [(String, Snapshot)] = [
            ("running", Fixtures.running(now)),
            ("idle-changes", Fixtures.idleChanges(now)),
            ("idle-clear", Fixtures.idleClear(now)),
            ("paused", Fixtures.paused(now)),
            ("failed", Fixtures.failed(now)),
            ("empty", Fixtures.empty(now)),
            ("first-run", Fixtures.firstRun(now)),
            ("hover", Fixtures.hover(now)),
        ]
        for (name, var snap) in states {
            snap.repoCount = 2
            let store = Store(snapshot: snap)
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                write(PopoverView(store: store, offscreen: true), dark: dark,
                      to: dir.appendingPathComponent("\(name)-\(suffix).png"), scale: 2)
            }
        }
        writeMenuBar(to: dir.appendingPathComponent("menubar.png"))
    }

    static func write<V: View>(_ view: V, dark: Bool, to url: URL, scale: CGFloat) {
        let p = Palette(dark ? .dark : .light)
        let content = view
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(p.ground)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("render failed: \(url.lastPathComponent)")
            return
        }
        do {
            try png.write(to: url)
            print("wrote \(url.path)")
        } catch {
            print("write failed: \(url.path): \(error.localizedDescription)")
        }
    }

    /// The glyph family on a light and a dark menu bar ground: a 4x row and a 1x row (the real size), in one PNG.
    static func writeMenuBar(to url: URL) {
        let states: [(String, GlyphState)] = [
            ("idle", .idle), ("running", .running(active: 3)), ("changes", .changesWaiting(count: 2)),
            ("paused", .paused), ("failed", .failed),
        ]
        let strip = VStack(alignment: .leading, spacing: 0) {
            bar(states, dark: false)
            bar(states, dark: true)
        }
        guard let rows4 = render(strip, scale: 4), let rows1 = render(strip, scale: 1) else {
            print("render failed: menubar")
            return
        }
        let width = max(rows4.width, rows1.width), height = rows4.height + rows1.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(rows1, in: CGRect(x: 0, y: 0, width: rows1.width, height: rows1.height))
        ctx.draw(rows4, in: CGRect(x: 0, y: rows1.height, width: rows4.width, height: rows4.height))
        guard let out = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else {
            print("render failed: menubar")
            return
        }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }

    private static func render<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    private static func bar(_ states: [(String, GlyphState)], dark: Bool) -> some View {
        let ground = dark ? Color(hex: "1E1E1E") : Color(hex: "ECECEC")
        let ink = dark ? NSColor.white : NSColor.black
        return HStack(spacing: 28) {
            ForEach(0..<states.count, id: \.self) { i in
                let (label, state) = states[i]
                VStack(spacing: 4) {
                    Image(nsImage: MenuGlyph.image(state, progress: 0.45, ink: ink, template: false))
                    Text(label).font(.system(size: 9)).foregroundColor(dark ? .white : .black).fixedSize()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ground)
    }

}

/// Fixtures for the design states. Repos are lumen/api and lumen/web; authors use first names.
enum Fixtures {
    static let schedule = ["07:00", "13:00", "19:00"].compactMap(ScheduleTime.init)

    static func pr(_ repo: String, _ n: Int, _ author: String, _ title: String, reason: String? = nil,
                   stage: Stage = .gather, active: Bool = false, verdict: Verdict? = nil, tokens: Int = 0,
                   carried: Bool = false) -> (String, PRState) {
        var state = PRState(n: n, author: author, title: title, stage: stage, active: active && verdict == nil,
                            verdict: verdict, reason: reason, tokens: tokens)
        if carried { state.carriedFrom = clockToday(10, 12, Date()) }
        return (repo, state)
    }

    static func run(_ id: String, now: Date, finished: Bool, prs: [(String, PRState)],
                    repos: [String] = ["lumen/api", "lumen/web"], error: String? = nil,
                    tokens: Int = 0) -> RunState {
        let started = clockToday(10, 12, now)
        return RunState(
            id: id, started: started, finished: finished ? started.addingTimeInterval(14 * 60) : nil,
            repos: repos.map { slug in
                RepoState(slug: slug, prs: prs.filter { $0.0 == slug }.map(\.1), error: nil)
            },
            tokens: tokens, error: error)
    }

    static func clockToday(_ h: Int, _ m: Int, _ now: Date) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
    }

    static func nextThirteen(_ now: Date) -> Date {
        Store.nextSweep(schedule: [ScheduleTime("13:00")!], after: now) ?? now
    }

    static func running(_ now: Date) -> Snapshot {
        let r = run("fixture-running", now: now, finished: false, prs: [
            pr("lumen/api", 1125, "ines", "Add rate limit headers to /v2 responses for partners", stage: .check, active: true, tokens: 212_000),
            pr("lumen/api", 1113, "tom", "Migrate invoices table to UUID keys, batched backfill", stage: .review, active: true, tokens: 96_000),
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve, tokens: 310_000),
            pr("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", reason: "missing RLS test", verdict: .changes, tokens: 260_000),
            pr("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", reason: "dates shift by a day", verdict: .changes, tokens: 240_000),
            pr("lumen/web", 91, "kai", "Redesign the empty states for the projects list", stage: .gather, active: true, tokens: 40_000),
            pr("lumen/web", 84, "sam", "Bump next to 15.1", reason: "draft", verdict: .skipped),
        ], tokens: 1_200_000)
        return Snapshot(run: r, running: true, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    static func idleChanges(_ now: Date) -> Snapshot {
        let r = run("fixture-idle", now: now, finished: true, prs: [
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", reason: "missing RLS test", verdict: .changes),
            pr("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", reason: "dates shift by a day", verdict: .changes),
            pr("lumen/web", 84, "sam", "Bump next to 15.1", reason: "draft", verdict: .skipped),
        ], tokens: 980_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    static func idleClear(_ now: Date) -> Snapshot {
        let r = run("fixture-clear", now: now, finished: true, prs: [
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("lumen/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: .approve),
            pr("lumen/web", 91, "kai", "Redesign the empty states for the projects list", verdict: .approve),
        ], tokens: 610_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    static func paused(_ now: Date) -> Snapshot {
        var s = idleChanges(now)
        s.paused = true
        s.pausedSince = clockToday(10, 35, now)
        return s
    }

    static func failed(_ now: Date) -> Snapshot {
        let r = run("fixture-failed", now: now, finished: true, prs: [
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", reason: "missing RLS test", verdict: .changes, carried: true),
            pr("lumen/web", 91, "kai", "Redesign the empty states for the projects list", verdict: .approve, carried: true),
        ], error: "claude exited 1: see the log for details\nFull log: ~/Library/Logs/glidepath.log", tokens: 70_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    static func empty(_ now: Date) -> Snapshot {
        let r = run("fixture-empty", now: now, finished: true, prs: [])
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    static func firstRun(_ now: Date) -> Snapshot {
        Snapshot(run: nil, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    static func hover(_ now: Date) -> Snapshot {
        var s = running(now)
        s.hovered = "lumen/api#1113"
        return s
    }
}
