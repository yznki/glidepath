import SwiftUI
import AppKit

/// The menu bar app. Same binary as the CLI: `review-radar` with no arguments (or `app`) lands here.
struct ReviewRadarApp: App {
    init() {
        // QA render path: draw PNGs from fixtures, then exit before any UI starts.
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

/// Renders the popover from fixtures for README screenshots and layout checks. Not used by the running app.
@MainActor
enum Snapshotter {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()

        let mid = Store(snapshot: midRun(now: now))
        write(PopoverView(store: mid, offscreen: true), dark: false, to: dir.appendingPathComponent("running-light.png"))
        write(PopoverView(store: mid, offscreen: true), dark: true, to: dir.appendingPathComponent("running-dark.png"))

        let idle = Store(snapshot: idle(now: now))
        write(PopoverView(store: idle, offscreen: true), dark: false, to: dir.appendingPathComponent("idle-light.png"))
        write(PopoverView(store: idle, offscreen: true), dark: true, to: dir.appendingPathComponent("idle-dark.png"))

        let paused = Store(snapshot: paused(now: now))
        write(PopoverView(store: paused, offscreen: true), dark: true, to: dir.appendingPathComponent("paused-dark.png"))
    }

    static func write<V: View>(_ view: V, dark: Bool, to url: URL) {
        let ground = dark ? Color(white: 0.13) : Color(white: 0.96)
        let content = view
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(ground)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
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

    static func pr(_ repo: String, _ n: Int, _ author: String?, _ reason: String?, stage: Stage,
                   active: Bool = false, verdict: Verdict? = nil, tokens: Int = 0) -> PRState {
        PRState(n: n, author: author, title: nil, stage: stage, active: active && verdict == nil,
                verdict: verdict, reason: reason, tokens: tokens)
    }

    static func run(_ id: String, now: Date, finished: Bool, prs: [(String, [PRState])], error: String? = nil) -> RunState {
        RunState(id: id,
                 started: now.addingTimeInterval(-21 * 60),
                 finished: finished ? now.addingTimeInterval(-60) : nil,
                 repos: prs.map { RepoState(slug: $0.0, prs: $0.1, error: nil) },
                 tokens: 1_480_000,
                 error: error)
    }

    static func midRun(now: Date) -> Snapshot {
        let r = run("fixture-running", now: now, finished: false, prs: [
            ("acme/api", [
                pr("acme/api", 1125, "ines", nil, stage: .check, active: true, tokens: 212_000),
                pr("acme/api", 1113, "tom", "api contracts", stage: .review, active: true, tokens: 96_000),
                pr("acme/api", 1101, "kai", nil, stage: .gather, active: true),
                pr("acme/api", 1229, "dana", nil, stage: .post, verdict: .approve, tokens: 310_000),
                pr("acme/api", 1212, "omar", "missing test", stage: .post, verdict: .changes, tokens: 260_000),
            ]),
            ("acme/web", [
                pr("acme/web", 88, "lea", "export leaks tenant id", stage: .post, verdict: .changes, tokens: 240_000),
                pr("acme/web", 84, "sam", "draft", stage: .gather, verdict: .skipped),
            ]),
        ])
        return Snapshot(run: r, running: true, paused: false, jobInstalled: true,
                        nextRun: now.addingTimeInterval(2 * 3600), postsReviews: false, lastError: nil)
    }

    static func idle(now: Date) -> Snapshot {
        let r = run("fixture-idle", now: now, finished: true, prs: [
            ("acme/api", [
                pr("acme/api", 1229, "dana", nil, stage: .post, verdict: .approve, tokens: 310_000),
                pr("acme/api", 1212, "omar", "missing test", stage: .post, verdict: .changes, tokens: 260_000),
                pr("acme/api", 1183, "sam", "head moved", stage: .gather, verdict: .skipped),
            ]),
            ("acme/web", [
                pr("acme/web", 88, "lea", "export leaks tenant id", stage: .post, verdict: .changes, tokens: 240_000),
            ]),
        ])
        return Snapshot(run: r, running: false, paused: false, jobInstalled: true,
                        nextRun: now.addingTimeInterval(2 * 3600 + 41 * 60), postsReviews: false, lastError: nil)
    }

    static func paused(now: Date) -> Snapshot {
        var s = idle(now: now)
        s.paused = true
        return s
    }
}
