import SwiftUI
import AppKit

/// The menu bar app. Same binary as the CLI: `glidepath` with no arguments (or `app`) lands here.
struct GlidepathApp: App {
    init() {
        // Snapshot rendering: draw the fixtures to PNGs, then exit before any UI starts.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let outDir = args[i + 1]
            MainActor.assumeIsolated { Snapshotter.run(outDir: outDir) }
            exit(0)
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
        for (name, snap) in states {
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

    /// The glyph states on a light and a dark menu bar ground, at 4x.
    static func writeMenuBar(to url: URL) {
        let states: [(String, GlyphState)] = [
            ("idle", .idle), ("running", .running(active: 3)), ("changes", .changesWaiting),
            ("paused", .paused), ("failed", .failed),
        ]
        let strip = VStack(alignment: .leading, spacing: 0) {
            bar(states, dark: false)
            bar(states, dark: true)
        }
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 4
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("render failed: menubar")
            return
        }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }

    private static func bar(_ states: [(String, GlyphState)], dark: Bool) -> some View {
        let ground = dark ? Color(hex: "1E1E1E") : Color(hex: "ECECEC")
        let ink = dark ? NSColor.white : NSColor.black
        return HStack(spacing: 28) {
            ForEach(0..<states.count, id: \.self) { i in
                let (label, state) = states[i]
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(nsImage: MenuGlyph.image(state, angle: -60, ink: ink,
                                                       template: false))
                            .resizable()
                            .frame(width: 18, height: 18)
                        if case .running(let n) = state {
                            Text("\(n)").font(.system(size: 13)).foregroundColor(dark ? .white : .black)
                        }
                    }
                    Text(label).font(.system(size: 9)).foregroundColor(dark ? .white : .black)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ground)
    }
}

/// Mock data for the design states. Repos are acme/api and acme/web; authors use first names.
enum Fixtures {
    static func pr(_ repo: String, _ n: Int, _ author: String, _ title: String, reason: String? = nil,
                   stage: Stage = .gather, active: Bool = false, verdict: Verdict? = nil, tokens: Int = 0) -> (String, PRState) {
        (repo, PRState(n: n, author: author, title: title, stage: stage, active: active && verdict == nil,
                       verdict: verdict, reason: reason, tokens: tokens))
    }

    static func run(_ id: String, now: Date, finished: Bool, prs: [(String, PRState)],
                    repos: [String] = ["acme/api", "acme/web"], error: String? = nil,
                    repoError: [String: String] = [:], tokens: Int = 0) -> RunState {
        let started = clockToday(10, 12, now)
        return RunState(
            id: id, started: started, finished: finished ? started.addingTimeInterval(14 * 60) : nil,
            repos: repos.map { slug in
                RepoState(slug: slug, prs: prs.filter { $0.0 == slug }.map(\.1), error: repoError[slug])
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
            pr("acme/api", 1125, "ines", "Add rate limit headers to /v2 responses", stage: .check, active: true, tokens: 212_000),
            pr("acme/api", 1113, "tom", "Migrate invoices table to UUID keys", stage: .review, active: true, tokens: 96_000),
            pr("acme/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve, tokens: 310_000),
            pr("acme/api", 1212, "omar", "Cache org permissions per request", reason: "missing RLS test", verdict: .changes, tokens: 260_000),
            pr("acme/web", 88, "lea", "Fix date picker timezone on export", reason: "dates shift by a day", verdict: .changes, tokens: 240_000),
            pr("acme/web", 91, "kai", "Redesign empty states for projects list", stage: .gather, active: true, tokens: 40_000),
            pr("acme/web", 84, "sam", "Bump next to 15.1", reason: "draft", verdict: .skipped),
        ], tokens: 1_200_000)
        return Snapshot(run: r, running: true, jobInstalled: true, nextRun: nextThirteen(now))
    }

    static func idleChanges(_ now: Date) -> Snapshot {
        let r = run("fixture-idle", now: now, finished: true, prs: [
            pr("acme/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("acme/api", 1212, "omar", "Cache org permissions per request", reason: "missing RLS test", verdict: .changes),
            pr("acme/web", 88, "lea", "Fix date picker timezone on export", reason: "dates shift by a day", verdict: .changes),
            pr("acme/web", 84, "sam", "Bump next to 15.1", reason: "draft", verdict: .skipped),
        ], tokens: 980_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now))
    }

    static func idleClear(_ now: Date) -> Snapshot {
        let r = run("fixture-clear", now: now, finished: true, prs: [
            pr("acme/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("acme/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: .approve),
            pr("acme/web", 91, "kai", "Redesign empty states for projects list", verdict: .approve),
        ], tokens: 610_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now))
    }

    static func paused(_ now: Date) -> Snapshot {
        var s = idleChanges(now)
        s.paused = true
        s.pausedSince = clockToday(10, 35, now)
        return s
    }

    static func failed(_ now: Date) -> Snapshot {
        let r = run("fixture-failed", now: now, finished: true, prs: [
            pr("acme/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("acme/api", 1212, "omar", "Cache org permissions per request"),
            pr("acme/web", 91, "kai", "Redesign empty states for projects list"),
        ], error: "claude exited 1: see the log for details\nFull log: ~/Library/Logs/glidepath.log", tokens: 70_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now))
    }

    static func empty(_ now: Date) -> Snapshot {
        let r = run("fixture-empty", now: now, finished: true, prs: [])
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now))
    }

    static func firstRun(_ now: Date) -> Snapshot {
        Snapshot(run: nil, jobInstalled: true, nextRun: nextThirteen(now))
    }

    static func hover(_ now: Date) -> Snapshot {
        var s = running(now)
        s.hovered = "acme/api#1113"
        return s
    }
}
