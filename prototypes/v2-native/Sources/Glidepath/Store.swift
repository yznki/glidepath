import SwiftUI
import Observation

enum Scenario: String, CaseIterable, Identifiable {
    case allGood = "All good", checking = "Checking", needsYou = "Needs you", problem = "Problem", paused = "Paused",
         stuck = "Stuck", slowReviewer = "Slow reviewer", holdingBack = "Holding back", quietHours = "Quiet hours", firstLaunch = "First launch"
    var id: String { rawValue }
}

enum Page: String, CaseIterable, Identifiable {
    case inbox = "Inbox", prs = "PRs", activity = "Activity", repos = "Repos"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .prs: "arrow.triangle.pull"
        case .activity: "clock"
        case .repos: "books.vertical"
        }
    }
}

enum Inspected: Hashable { case pr(String), repo(String) }
enum ActivityFilter: String, CaseIterable { case all = "All", reviews = "Reviews", yours = "Your PRs", problems = "Problems" }
enum SettingsPane: String { case general, schedule, behaviour, advanced }
enum Mode: String { case askFirst = "Ask first", autopilot = "Autopilot" }

struct Status {
    var text: String
    var button: String
    var symbol: String
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var canUndo: Bool
}

struct WorkItem: Identifiable { let id: String; var stage: String }

/// What the glide line shows. One value, read by the window header, the popover and the menu bar.
enum LineMode { case quiet, checking, needs, problem, paused }

/// Why Glidepath is holding work back on its own (not a pause you chose).
enum Hold { case reserve, quiet }

/// The single source of truth. The Needs you count is computed here once and read by the
/// menu bar label, the popover, the sidebar badge and the Inbox title.
@MainActor @Observable
final class Store {
    var scenario: Scenario = .needsYou
    var prs: [PR] = Seed.prs
    var activity: [ActivityItem] = Seed.activity
    var repos: [Repo] = Seed.repos
    var since = ""

    var page: Page = .inbox
    var inspected: Inspected?
    var showInspector = false
    var yourTab = false
    var activityFilter: ActivityFilter = .all
    var search = ""
    var showDone = false
    var banner: Banner?
    var showShortcuts = false
    var showOnboarding = false
    var showLog = false
    var spaceHeld = false
    var settingsPane: SettingsPane = .general

    var checking = false
    var checkStarted = Date.distantPast
    let checkPeriod = 3.0           // one tracer pass per PR
    var landing: String?            // the PR whose row is gliding into Done today
    var debugHold: String?          // prototype: holds a row's button from a script
    var morphFrom: String?          // the row whose glass is growing into the inspector
    @ObservationIgnored var rowFrames: [String: CGRect] = [:]      // in the Inbox's scroll content
    @ObservationIgnored var rowViews: [String: NSView] = [:]
    @ObservationIgnored var inspectorView: NSView?
    var working: [WorkItem] = []
    var problem = false
    var pausedUntil: String?
    var hold: Hold?
    var usage = 54.0                // % of the current 5-hour Claude window

    // Settings
    var mode: Mode = .askFirst
    var postAs = "Full review"
    var strictness = "Balanced"
    var sizeLimit = 1200
    var openAtLogin = true
    var showInMenuBar = true
    var notifications = "Needs you only"
    var preset = "Workday"
    var times: [Date] = [9, 13, 17].map { Store.time($0) }
    var days = [true, true, true, true, true, false, false]
    var quietFrom = Store.time(19)
    var quietTo = Store.time(8)
    var quietWeekend = true
    var reserve = 20.0
    var model = "Sonnet"
    var budget = 5.0
    var linearKey = ""

    private var checkTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    // Hooks the views install so the store can reach scene actions.
    @ObservationIgnored var openMain: () -> Void = {}
    @ObservationIgnored var openSettingsAction: () -> Void = {}
    @ObservationIgnored var togglePopover: () -> Void = {}

    init() { apply(.needsYou) }

    static func time(_ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
    }

    // MARK: Needs you, computed in one place

    var needsYou: [PR] { prs.filter { $0.need != nil }.sorted { $0.since < $1.since } }
    var needsCount: Int { needsYou.count }

    var status: Status {
        if problem { return Status(text: "Can't reach GitHub: sign-in expired.", button: "Fix", symbol: "exclamationmark.triangle") }
        if let pausedUntil { return Status(text: "Paused until \(pausedUntil).", button: "Resume", symbol: "pause.circle") }
        if hold == .reserve {
            return Status(text: "Holding back: \(Int(reserve))% of your usage is kept for you. Resumes 4:10 PM.", button: "Adjust", symbol: "gauge.with.dots.needle.50percent")
        }
        if hold == .quiet { return Status(text: "Waiting for quiet hours to finish 3 fixes.", button: "Run now", symbol: "play") }
        if checking {
            let n = max(working.count, 1)
            return Status(text: "Checking \(n) PR\(n == 1 ? "" : "s") in lumen/web…", button: "Stop", symbol: "stop.fill")
        }
        if needsCount > 0 {
            return Status(text: needsCount == 1 ? "1 thing needs you." : "\(needsCount) things need you.", button: "Open", symbol: "macwindow")
        }
        return Status(text: "All good. Next check at 5:00 PM.", button: "Check now", symbol: "arrow.clockwise")
    }

    /// The window's toolbar never offers "Open": it is already open.
    var windowStatus: Status {
        var s = status
        if s.button == "Open" { s.button = "Check now"; s.symbol = "arrow.clockwise" }
        return s
    }

    var lineMode: LineMode {
        if problem { return .problem }
        if pausedUntil != nil || hold != nil { return .paused }
        if checking { return .checking }
        return needsCount > 0 ? .needs : .quiet
    }

    var doneToday: [ActivityItem] {
        activity.filter { $0.day == 0 && [.review, .mine, .skip].contains($0.kind) }
    }

    func pr(_ id: String) -> PR? { prs.first { $0.id == id } }
    func index(_ id: String) -> Int? { prs.firstIndex { $0.id == id } }

    // MARK: Scenarios

    func apply(_ s: Scenario) {
        checkTask?.cancel()
        scenario = s
        prs = Seed.prs; activity = Seed.activity; repos = Seed.repos
        checking = false; working = []; problem = false; pausedUntil = nil; hold = nil; usage = 54; banner = nil
        showOnboarding = false; since = "Posted 4 reviews, merged #1246"
        inspected = nil; showInspector = false
        switch s {
        case .needsYou:
            break
        case .stuck, .slowReviewer:
            for id in ["api-1253", "api-1301", "web-1250"] { resolve(id, quiet: true) }
            if s == .stuck, let i = index("api-1310") {
                prs[i].need = .stuck; prs[i].steps[0] = .needs
                prs[i].reason = "Tried twice to fix the failing lint step; the error is in generated code."
                prs[i].timeline.insert(Moment(time: "1:48 PM", text: "Stopped after two tries: src/gen/billing.ts is generated, so a hand fix would be overwritten"), at: 0)
            }
            if s == .slowReviewer, let i = index("api-1305") { prs[i].need = .ping }
        case .allGood, .checking, .problem, .paused, .holdingBack, .quietHours:
            for id in ["web-1276", "api-1253", "api-1301", "web-1250"] { resolve(id, quiet: true) }
            since = "Posted 5 reviews, pushed a fix to #1253, merged #1301"
            if s == .checking { checkNow() }
            if s == .problem {
                problem = true
                activity.insert(ActivityItem(day: 0, time: "2:02 PM", kind: .problem,
                                             text: "Can't reach GitHub: sign-in expired. New checks wait until you sign in again.", fix: "Fix"), at: 0)
            }
            if s == .paused { pausedUntil = "tomorrow at 9:00 AM" }
            if s == .holdingBack { hold = .reserve; usage = 81 }
            if s == .quietHours { hold = .quiet }
        case .firstLaunch:
            activity = []; since = ""
            for i in prs.indices {
                prs[i].need = nil
                if !prs[i].mine { prs[i].state = .unchecked; prs[i].reason = "Not checked yet." }
                else { prs[i].lookAfter = false }
            }
            showOnboarding = true
        }
    }

    // MARK: Actions

    /// Runs after a completed hold. Everything here goes to GitHub as you.
    func perform(_ id: String) {
        guard pr(id)?.need != nil else { return }
        resolve(id, quiet: false)
    }

    /// A completed hold. On the Inbox the row glides into Done today first; elsewhere it just happens.
    func complete(_ id: String) {
        guard pr(id)?.need != nil, landing == nil else { return }
        if pr(id)?.need == .stuck {
            withAnimation(.glide) { perform(id) }
            show(Banner(text: "Trying again on #1310. Nothing goes to GitHub until it works.", canUndo: false))
        } else if page == .inbox { landing = id } else { withAnimation(.glide) { perform(id) } }
    }

    /// Selecting a row opens the inspector; its glass grows out of the row.
    func select(_ id: String?) {
        if let id, !showInspector, page == .inbox { morphFrom = id }
        inspected = id.map(Inspected.pr)
        showInspector = id != nil
    }

    private func resolve(_ id: String, quiet: Bool) {
        guard let i = index(id), let need = prs[i].need else { return }
        prs[i].need = nil
        let t = "2:14 PM"
        switch need {
        case .post:
            prs[i].state = .reviewed
            prs[i].reason = "Posted at \(t): \(prs[i].verdict.lowercased())."
            if !quiet { log(.review, "Posted a review: \(prs[i].verdict.lowercased()).", id) }
        case .push:
            prs[i].group = .onIt; prs[i].steps[0] = .running
            prs[i].reason = "Pushed the fix. Waiting for CI."
            prs[i].timeline.insert(Moment(time: t, text: "Pushed the fix (a3f9c1)"), at: 0)
            if !quiet { log(.mine, "Pushed a fix.", id) }
        case .reply:
            prs[i].group = .waiting; prs[i].steps[1] = .done
            prs[i].reason = "Replied to Gadi. Waiting for approval."
            prs[i].timeline.insert(Moment(time: t, text: "Replied to Gadi and resolved the thread"), at: 0)
            if !quiet { log(.mine, "Replied to Gadi and resolved the thread.", id) }
        case .merge:
            prs[i].group = .merged; prs[i].steps[3] = .done
            prs[i].reason = "Merged today at \(t)."
            prs[i].timeline.insert(Moment(time: t, text: "Merged"), at: 0)
            if !quiet { log(.mine, "Merged.", id) }
        case .revert:
            if !quiet { log(.mine, "Opened a revert PR.", id) }
        case .stuck:
            prs[i].group = .onIt; prs[i].steps[0] = .running
            prs[i].reason = "Trying again: regenerating the client before linting."
            prs[i].timeline.insert(Moment(time: t, text: "You asked to try again: regenerating the client first"), at: 0)
        case .ping:
            prs[i].reason = "Pinged today. Waiting on Gadi."
            prs[i].timeline.insert(Moment(time: t, text: "Pinged Gadi for a review"), at: 0)
            if !quiet { log(.mine, "Pinged Gadi today for a review.", id) }
        }
    }

    /// Instant, with Undo for 8 seconds and ⌘Z.
    func discard(_ id: String, undo: UndoManager?) {
        guard let i = index(id), prs[i].need != nil else { return }
        let before = prs[i]
        prs[i].need = nil
        if !before.mine { prs[i].state = .reviewed; prs[i].reason = "Review discarded. Nothing was posted." }
        else { prs[i].reason = "Discarded. Glidepath will look again at the next check." }
        undo?.registerUndo(withTarget: self) { s in MainActor.assumeIsolated { s.restore(before) } }
        undo?.setActionName("Discard")
        show(Banner(text: "Discarded \(before.need?.label.lowercased() ?? "") for \(before.shortRef).", canUndo: true))
    }

    func removeRepo(_ name: String, undo: UndoManager?) {
        guard let i = repos.firstIndex(where: { $0.name == name }) else { return }
        let r = repos.remove(at: i)
        if inspected == .repo(name) { inspected = nil; showInspector = false }
        undo?.registerUndo(withTarget: self) { s in MainActor.assumeIsolated { s.repos.insert(r, at: min(i, s.repos.count)) } }
        undo?.setActionName("Remove Repo")
        show(Banner(text: "Removed \(name).", canUndo: true))
    }

    private func restore(_ p: PR) {
        if let i = index(p.id) { prs[i] = p }
        banner = nil
    }

    func undoBanner(_ undo: UndoManager?) {
        undo?.undo()
        banner = nil
    }

    private func show(_ b: Banner) {
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = b }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { self?.banner = nil }
        }
    }

    private func log(_ kind: ActivityKind, _ text: String, _ pr: String?) {
        activity.insert(ActivityItem(day: 0, time: "2:14 PM", kind: kind, text: text, pr: pr), at: 0)
    }

    func primary() {
        switch status.button {
        case "Fix": problem = false; show(Banner(text: "Signed in to GitHub again.", canUndo: false))
        case "Resume": pausedUntil = nil
        case "Run now": hold = nil; checkNow()
        case "Adjust": settingsPane = .schedule; openSettingsAction()
        case "Stop": stop()
        case "Open": openMain()
        default: checkNow()
        }
    }

    func checkNow() {
        guard !checking else { return }
        let targets = prs.filter { !$0.mine && $0.state == .unchecked }.prefix(3)
        guard !targets.isEmpty else {
            show(Banner(text: "Checked 3 repos. Nothing new.", canUndo: false)); return
        }
        checking = true
        checkStarted = .now
        working = targets.map { WorkItem(id: $0.id, stage: "Reading the diff") }
        checkTask = Task { [weak self] in
            for stage in ["Checking findings", "Writing the review"] {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                withAnimation { self.working = self.working.map { WorkItem(id: $0.id, stage: stage) } }
            }
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            withAnimation {
                for w in self.working {
                    guard let i = self.index(w.id) else { continue }
                    if self.mode == .askFirst {
                        self.prs[i].state = .ready; self.prs[i].need = .post
                        self.prs[i].since = 10 + i
                        self.prs[i].reason = "\(self.prs[i].verdict): review written, waiting for you."
                    } else {
                        self.prs[i].state = .reviewed
                        self.prs[i].reason = "Posted at 2:14 PM: \(self.prs[i].verdict.lowercased())."
                    }
                }
                self.checking = false; self.working = []
            }
        }
    }

    func stop() {
        checkTask?.cancel()
        withAnimation { checking = false; working = [] }
        show(Banner(text: "Stopped. Nothing was posted.", canUndo: false))
    }

    func pause(_ label: String) { pausedUntil = label; checkTask?.cancel(); checking = false; working = [] }

    /// Opens the window on a PR (used by the popover rows and Activity).
    func open(_ id: String) {
        page = .inbox
        if let p = pr(id), p.need == nil { page = .prs; yourTab = p.mine }
        inspected = .pr(id)
        showInspector = true
        openMain()
    }

    // MARK: Debug hooks for screenshots (prototype only)

    func handleDebug(_ cmd: String) {
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "scenario": if let s = Scenario.allCases.first(where: { $0.rawValue == arg }) { apply(s) }
        case "page": if let p = Page(rawValue: arg) { page = p; showInspector = false; inspected = nil }
        case "pr": page = (pr(arg)?.need != nil) ? .inbox : .prs; yourTab = pr(arg)?.mine ?? false; inspected = .pr(arg); showInspector = true
        case "repo": page = .repos; inspected = .repo(arg); showInspector = true
        case "your": yourTab = arg == "1"
        case "settings": settingsPane = SettingsPane(rawValue: arg) ?? .general; openSettingsAction()
        case "popover": togglePopover()
        case "activate": openMain()
        case "inspector": showInspector = arg == "1"
        case "done": showDone = arg == "1"
        case "shot": WindowShot.capture(to: arg)
        case "glyphs": LineGlyph.sheet(to: arg)
        case "backdrop": Backdrop.show(arg == "1")
        case "closeothers": NSApp.windows.filter { $0.isVisible && $0.title != "Inbox" && $0.styleMask.contains(.titled) && !$0.title.isEmpty && Page(rawValue: $0.title) == nil }.forEach { $0.close() }
        case "hold":
            debugHold = arg
            Task { try? await Task.sleep(for: .seconds(0.8)); debugHold = nil }
        case "holdshots":   // holdshots:<id>:<prefix>, frames mid-signature
            let a = arg.split(separator: ":", maxSplits: 1).map(String.init)
            handleDebug("hold:\(a[0])")
            for (i, t) in [0.3, 0.75, 1.0, 1.25, 2.0].enumerated() {
                Task { try? await Task.sleep(for: .seconds(t)); WindowShot.capture(to: "\(a[1])-f\(i)") }
            }
        case "selectshots":  // selectshots:<id>:<prefix>, frames mid-morph
            let a = arg.split(separator: ":", maxSplits: 1).map(String.init)
            page = .inbox; showInspector = false; inspected = nil
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                select(a[0])
                for (i, t) in [0.12, 0.25, 0.8].enumerated() {
                    Task { try? await Task.sleep(for: .seconds(t)); WindowShot.capture(to: "\(a[1])-f\(i)") }
                }
            }
        default: break
        }
    }
}

/// Prototype only: the app captures its own windows (no Screen Recording permission needed).
/// Usage: "shot:/path/prefix" writes prefix-<n>-<title>.png for every visible window.
enum WindowShot {
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    static func capture(to prefix: String) {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(sym, to: Fn.self)
        for (n, w) in NSApp.windows.enumerated() where w.isVisible && w.frame.height > 40 {
            // kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1
            guard let img = create(.null, 8, UInt32(w.windowNumber), 1)?.takeRetainedValue() else { continue }
            let rep = NSBitmapImageRep(cgImage: img)
            let name = w.title.isEmpty ? String(describing: type(of: w)) : w.title
            let url = URL(fileURLWithPath: "\(prefix)-\(n)-\(name.replacingOccurrences(of: " ", with: "_")).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

/// Prototype only: a dark night-sky "wallpaper" window behind the main window, to check the smoked glass on a dark desktop
/// without touching the real wallpaper. tools/cap.swift composites it like the wallpaper.
@MainActor enum Backdrop {
    static var window: NSWindow?
    static func show(_ on: Bool) {
        window?.orderOut(nil); window = nil
        guard on, let main = NSApp.windows.first(where: { $0.title == "Inbox" || Page(rawValue: $0.title) != nil }) else { return }
        let w = NSWindow(contentRect: main.screen?.frame ?? main.frame.insetBy(dx: -60, dy: -60), styleMask: .borderless, backing: .buffered, defer: false)
        w.title = "Backdrop"
        w.contentView = NSHostingView(rootView: LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.12), Color(red: 0.10, green: 0.07, blue: 0.20),
                                                                         Color(red: 0.02, green: 0.09, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
        w.level = .normal
        w.order(.below, relativeTo: main.windowNumber)
        window = w
    }
}
