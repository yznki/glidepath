import SwiftUI

@MainActor let store = Store()

@main
struct GlidepathApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Glidepath", id: "main") {
            MainWindow()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(.graphite)
                // The wallpaper reads through the whole window, like Control Center.
                .containerBackground(for: .window) { SmokedGlass() }
                .background(HookInstaller())
        }
        .defaultSize(width: 1180, height: 740)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(.graphite)
        }
    }
}

/// Smoked glass: the wallpaper still shows through, blurred, but the tone stays near-black and calm on any wallpaper.
struct SmokedGlass: View {
    var body: some View {
        ZStack {
            // Stays glass when another app is in front.
            Rectangle().fill(.ultraThinMaterial).materialActiveAppearance(.active)
            Color.black.opacity(0.52)
        }
    }
}

/// Lets the store open the window and Settings from anywhere.
struct HookInstaller: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.onAppear {
            store.openMain = { openWindow(id: "main"); NSApp.activate() }
            store.openSettingsAction = { openSettings(); NSApp.activate() }
        }
    }
}

struct AppCommands: Commands {
    let store: Store

    var body: some Commands {
        CommandMenu("Controls") {
            Button("Check Now") { store.checkNow() }
                .keyboardShortcut("r")
                .disabled(store.checking || store.pausedUntil != nil)
            Button("Stop") { store.stop() }
                .keyboardShortcut(".")
                .disabled(!store.checking)
            Menu("Pause") { PauseItems().environment(store) }
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(Page.allCases.enumerated()), id: \.offset) { i, page in
                Button(page.rawValue) {
                    store.page = page; store.inspected = nil; store.showInspector = false
                    store.openMain()
                }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
            }
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { store.showShortcuts = true }
                .keyboardShortcut("/")
        }
        CommandMenu("Prototype") {
            Picker("Scenario", selection: Binding(get: { store.scenario }, set: { store.apply($0) })) {
                ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        statusItem = MainActor.assumeIsolated { StatusItem() }
        // Prototype only: lets a script drive scenarios and pages for screenshots.
        DistributedNotificationCenter.default().addObserver(forName: .init("glidepath.proto"), object: nil, queue: .main) { note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated { store.handleDebug(cmd) }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Check Now", action: #selector(checkNow), keyEquivalent: "").target = self
        let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, until) in [("For 1 Hour", "3:14 PM"), ("For 3 Hours", "5:14 PM"), ("Until Tomorrow", "tomorrow at 9:00 AM")] {
            let item = sub.addItem(withTitle: title, action: #selector(pauseItem(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = until
        }
        pause.submenu = sub
        menu.addItem(pause)
        return menu
    }

    @objc private func checkNow() { MainActor.assumeIsolated { store.checkNow() } }
    @objc private func pauseItem(_ item: NSMenuItem) {
        let until = item.representedObject as? String ?? ""
        MainActor.assumeIsolated { store.pause(until) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { store.openMain() } }
        return true
    }
}

/// The menu bar item: the glide line as a template image, the count beside it, a glass popover on click
/// and the native menu on right click. AppKit-hosted: SwiftUI's MenuBarExtra re-renders its button on every
/// animation frame anywhere in the app, which the living line would turn into a busy loop.
@MainActor final class StatusItem: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var timer: Timer?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView().environment(store).preferredColorScheme(.dark).tint(.graphite))
        item.button?.target = self
        item.button?.action = #selector(click)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        store.togglePopover = { [weak self] in self?.toggle() }
        render()
    }

    /// Redraws only when the line's state or the count changes; a 1/8 s tick moves the dot while checking.
    private func render() {
        let mode = withObservationTracking {
            let m = store.lineMode
            item.button?.title = store.needsCount > 0 && m != .problem && m != .paused ? "\(store.needsCount)" : ""
            return m
        } onChange: {
            Task { @MainActor [weak self] in self?.render() }
        }
        item.button?.setAccessibilityLabel(store.status.text)
        timer?.invalidate(); timer = nil
        if mode == .checking {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.item.button?.image = LineGlyph.cached(mode: .checking, phase: Date.now.timeIntervalSince(store.checkStarted) / store.checkPeriod)
                }
            }
        }
        item.button?.image = LineGlyph.cached(mode: mode)
    }

    @objc private func click() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item.button else { return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Check Now", action: #selector(checkNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Glidepath", action: #selector(openMain), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Glidepath", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func checkNow() { store.checkNow() }
    @objc private func openMain() { store.openMain() }
    @objc private func settings() { store.openSettingsAction() }
}
