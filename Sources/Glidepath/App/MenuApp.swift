import SwiftUI
import AppKit

/// The menu bar app. Same binary as the CLI: `glidepath` with no arguments (or `app`) lands here.
struct GlidepathApp: App {
    @NSApplicationDelegateAdaptor(GlidepathAppDelegate.self) private var appDelegate

    init() {
        let args = CommandLine.arguments
        // Snapshot rendering: draw the fixtures to PNGs, then exit before any UI starts.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let outDir = args[i + 1]
            MainActor.assumeIsolated { Snapshotter.run(outDir: outDir) }
            exit(0)
        }
        if args.count == 1 || args.dropFirst().first == "app" {
            MainActor.assumeIsolated { GlobalHotkey.shared.applyConfig(Paths()) }
        }
    }

    var body: some Scene {
        // SwiftUI opens the first scene at launch. This one is never inserted, so the app starts with no window; the
        // status item (MenuBar) opens the main window when it is wanted.
        MenuBarExtra("Glidepath", isInserted: .constant(false)) { EmptyView() }
        Window("Glidepath", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: WinMetrics.windowWidth, height: WinMetrics.windowHeight)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { GlidepathCommands() }
    }
}

/// Renders the design states from fixtures into docs/shots. Not used by the running app.
@MainActor
enum Snapshotter {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        writeDashboard(to: dir.appendingPathComponent("index.html"), now: now)
        writeWindowShots(to: dir.appendingPathComponent("app", isDirectory: true), now: now)
        writeShortcutsSheet(to: dir.appendingPathComponent("app", isDirectory: true))
        writeReviewSheets(to: dir)
    }

    /// The review sheet at 860 x 760, from the flight recorder fixtures: a landed changes review, a run with no result and
    /// a review that was not posted. Dark only, since the sheet's Gotham tokens are fixed. The sheet draws its settled state.
    static func writeReviewSheets(to dir: URL) {
        let store = Store(snapshot: Snapshot())
        let landed = WindowFixtures.reviewLanded()
        write(ReviewSheet(row: landed.row, text: landed.text, store: store, fixture: landed.artifacts, onClose: {})
                .environment(\.offscreenRender, true),
              dark: true, to: dir.appendingPathComponent("review-landed.png"), scale: 2)
        let stopped = WindowFixtures.reviewNoResult()
        write(ReviewSheet(row: stopped.row, text: nil, store: store, fixture: stopped.artifacts, onClose: {})
                .environment(\.offscreenRender, true),
              dark: true, to: dir.appendingPathComponent("review-noresult.png"), scale: 2)
        let notPosted = WindowFixtures.reviewNotPosted()
        write(ReviewSheet(row: notPosted.row, text: nil, store: store, fixture: notPosted.artifacts, onClose: {})
                .environment(\.offscreenRender, true),
              dark: true, to: dir.appendingPathComponent("review-notposted.png"), scale: 2)
    }

    /// Every window section and onboarding step, light and dark, from `WindowFixtures`. Each store is a fixture store,
    /// so nothing here reads the config, the state folders or launchd. Sections draw their scroll lists inline
    /// (`offscreenRender`), since ImageRenderer draws ScrollView blank.
    static func writeWindowShots(to dir: URL, now _: Date) {
        // Every window render reads the fixture clock, not the real one, so the renders match their mockups on any day.
        let now = WindowFixtures.clock
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The plane whose Approach drawer is open, and the Settings search, for the shots that show them.
        // The Settings search "tend" shows only the Tending group, which the shot needs in view.
        let sections: [(name: String, section: WindowSection, opened: String?, query: String)] = [
            ("now", .now, nil, ""), ("running", .now, nil, ""), ("now-clear", .now, nil, ""), ("now-dry-run", .now, nil, ""),
            ("approach", .approach, nil, ""), ("approach-drawer", .approach, "lumen/api#1246", ""),
            ("approach-landing", .approach, nil, ""),
            ("reviews", .reviews, nil, ""), ("repos", .repos, nil, ""), ("schedule", .schedule, nil, ""),
            ("settings", .settings, nil, ""), ("settings-tending", .settings, nil, "tend"),
            ("settings-playbook", .settings, nil, "playbook"),
        ]
        for entry in sections {
            let store = Store(snapshot: WindowFixtures.section(entry.name, now: now))
            let screen = WindowScreen(store: store, router: WindowRouter(section: entry.section, showOnboarding: false),
                                      approachOpen: entry.opened, settingsQuery: entry.query)
            let name = entry.name
            for dark in [true, false] {
                writeWindow(screen, dark: dark, to: dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        // Approach with the Edit sheet open on Gadi's call, the reply text drafted.
        let callStore = Store(snapshot: WindowFixtures.section("approach", now: now))
        let callScreen = WindowScreen(store: callStore, router: WindowRouter(section: .approach, showOnboarding: false),
                                      callOpen: "lumen/api#1246/\(WindowFixtures.gadiCallID)")
        for dark in [true, false] {
            writeWindow(callScreen, dark: dark, to: dir.appendingPathComponent("approach-call-edit-\(dark ? "dark" : "light").png"))
        }
        // Approach with the Split builder open on #1270's proposed split.
        let splitStore = Store(snapshot: WindowFixtures.section("approach", now: now))
        let splitScreen = WindowScreen(store: splitStore, router: WindowRouter(section: .approach, showOnboarding: false),
                                       splitOpen: "lumen/api#1270/split")
        for dark in [true, false] {
            writeWindow(splitScreen, dark: dark, to: dir.appendingPathComponent("approach-split-\(dark ? "dark" : "light").png"))
        }
        let steps: [(String, OnboardingStep, Bool)] = [
            ("onb-welcome", .welcome, false), ("onb-tools", .tools, false), ("onb-repos", .repos, false),
            ("onb-review", .review, false), ("onb-schedule", .schedule, false),
            ("onb-sweep", .firstSweep, true), ("onb-sweep-landed", .firstSweep, false),
        ]
        let paths = Paths()
        for (name, step, running) in steps {
            let store = Store(snapshot: Snapshot())
            let model = WindowFixtures.onboarding(step, now: now, paths: paths, running: running)
            let screen = WindowScreen(store: store, router: WindowRouter(showOnboarding: true), onboarding: model)
            for dark in [true, false] {
                writeWindow(screen, dark: dark, to: dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        // The first sweep at the 960x640 minimum: its footer must stay on screen.
        let minimal = WindowScreen(store: Store(snapshot: Snapshot()), router: WindowRouter(showOnboarding: true),
                                   onboarding: WindowFixtures.onboarding(.firstSweep, now: now, paths: paths))
        for dark in [true, false] {
            writeWindow(minimal, dark: dark, to: dir.appendingPathComponent("onb-sweep-640-\(dark ? "dark" : "light").png"),
                        width: WinMetrics.minWidth, height: WinMetrics.minHeight)
        }
    }

    /// The ⌘/ sheet, light and dark, at its own size: the same table the menus read.
    static func writeShortcutsSheet(to dir: URL) {
        for dark in [true, false] {
            writeWindow(ShortcutsSheet(), dark: dark,
                        to: dir.appendingPathComponent("shortcuts-\(dark ? "dark" : "light").png"),
                        width: 640, height: 720)
        }
    }

    /// One window screen in the mockup frame: 1100x720, radius 12, a 1 pt edge, the three fake traffic
    /// lights at (20, 20), and a 40 pt #2a2a2d backdrop. Drawn at 2x, so the PNG is 2360x1600 like the mockups.
    static func writeWindow<V: View>(_ view: V, dark: Bool, to url: URL,
                                     width: CGFloat = WinMetrics.windowWidth, height: CGFloat = WinMetrics.windowHeight) {
        let shape = RoundedRectangle(cornerRadius: 12)
        let framed = view
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                HStack(spacing: WinMetrics.s8) {
                    ForEach(["FF5F57", "FEBC2E", "28C840"], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 20)
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
            .padding(40)
            .frame(width: width + 80, height: height + 80)
            .background(Color(hex: "2A2A2D"))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.offscreenRender, true)
        // The window's colours are dynamic NSColors, which resolve against the drawing appearance.
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        var image: CGImage?
        (NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing())
            .performAsCurrentDrawingAppearance { image = renderer.cgImage }
        guard let cg = image,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("render failed: \(url.lastPathComponent)")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            print("wrote \(url.path)")
        } catch {
            print("write failed: \(url.path): \(error.localizedDescription)")
        }
    }

    /// The dashboard page for the fixture runs and one held draft. Written as HTML only; the browser screenshot is
    /// taken by hand.
    static func writeDashboard(to url: URL, now: Date) {
        let runs = Fixtures.dashboardRuns(now)
        let drafts = Fixtures.dashboardDrafts(now)
        var snap = Fixtures.drafts(now)
        snap.run = runs.first
        let header = HeaderCopy.make(Presentation.headerKind(snap, now: now), now: now, drafts: drafts.count)
        let html = DashboardPage.render(runs: runs, drafts: drafts, header: header, now: now)
        do {
            try Data(html.utf8).write(to: url, options: .atomic)
            print("wrote \(url.path)")
        } catch {
            print("write failed: \(url.path): \(error.localizedDescription)")
        }
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
}

/// Fixtures for the design states. Repos are lumen/api and lumen/web; authors use first names.
enum Fixtures {
    static let schedule = ["07:00", "13:00", "19:00"].compactMap(ScheduleTime.init)

    static func pr(_ repo: String, _ n: Int, _ author: String, _ title: String, reason: String? = nil,
                   stage: Stage = .gather, active: Bool = false, verdict: Verdict? = nil, tokens: Int = 0,
                   carried: Bool = false, draft: Bool = false, flagged: Bool = false) -> (String, PRState) {
        var state = PRState(n: n, author: author, title: title, stage: stage, active: active && verdict == nil,
                            verdict: verdict, reason: reason, tokens: tokens)
        if carried { state.carriedFrom = clockToday(10, 12, Date()) }
        if draft { state.draft = true }
        if flagged { state.flagged = true }
        return (repo, state)
    }

    static func shifted(_ run: RunState, by seconds: TimeInterval) -> RunState {
        var r = run
        r.started = r.started.addingTimeInterval(seconds)
        r.finished = r.finished?.addingTimeInterval(seconds)
        return r
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
        ScheduleTimes.nextSweep(after: now, times: [ScheduleTime("13:00")!]) ?? now
    }

    static func idleChanges(_ now: Date) -> Snapshot {
        let r = run("fixture-idle", now: now, finished: true, prs: [
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve, draft: true),
            pr("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", reason: "missing RLS test", verdict: .changes, draft: true),
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

    static func failed(_ now: Date) -> Snapshot {
        let r = run("fixture-failed", now: now, finished: true, prs: [
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            pr("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", reason: "missing RLS test", verdict: .changes, carried: true),
            pr("lumen/web", 91, "kai", "Redesign the empty states for the projects list", verdict: .approve, carried: true),
        ], error: "claude exited 1: see the log for details\nFull log: ~/Library/Logs/glidepath.log", tokens: 70_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    /// A newer release is out: the dot on the glyph, the line above the footer, and the first menu item.
    /// Draft mode: held reviews with Post and Discard on line 2, and a flagged row. The header says how many wait.
    static func drafts(_ now: Date) -> Snapshot {
        let r = run("fixture-drafts", now: now, finished: true, prs: [
            pr("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", reason: "missing RLS test", verdict: .changes, draft: true, flagged: true),
            pr("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve, draft: true),
            pr("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", reason: "dates shift by a day", verdict: .changes),
            pr("lumen/web", 84, "sam", "Bump next to 15.1", reason: "draft", verdict: .skipped),
        ], tokens: 980_000)
        return Snapshot(run: r, jobInstalled: true, nextRun: nextThirteen(now), schedule: schedule)
    }

    /// Four finished runs for the dashboard, newest first, and the draft from the newest one.
    static func dashboardRuns(_ now: Date) -> [RunState] {
        let day: TimeInterval = 24 * 3600
        return [
            drafts(now).run!,
            shifted(idleChanges(now).run!, by: -day),
            shifted(failed(now).run!, by: -2 * day),
            shifted(idleClear(now).run!, by: -3 * day),
        ]
    }

    static func dashboardDrafts(_ now: Date) -> [Drafts.Found] {
        let body = """
        Two things to fix before this lands.

        The rate limit is checked after the cache lookup, so a cached response skips it. Move the check above the lookup.

        The new query has no test for a caller from another org.
        """
        let draft = DraftFile(slug: "lumen/api", n: 1212, head: "0f3c9a7", event: "REQUEST_CHANGES", body: body,
                              comments: [PayloadComment(path: "internal/audit/cache.go", line: 42, side: "RIGHT",
                                                        body: "The lookup runs before the limit check here.")],
                              created: now.addingTimeInterval(-600))
        return [Drafts.Found(runId: "fixture-drafts", path: "", draft: draft)]
    }

}
