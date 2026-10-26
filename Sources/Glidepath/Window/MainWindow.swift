import SwiftUI
import AppKit

/// The main window's content: sidebar beside the canvas. `MainWindow` hosts it in an AppKit window; the layout is in
/// `WindowScreen`, which snapshot rendering draws on its own.
struct MainWindowView: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var store: Store

    init(store: Store? = nil, router: WindowRouter? = nil) {
        self.store = store ?? Store.shared
        self.router = router ?? WindowRouter.shared
    }

    var body: some View {
        WindowScreen(store: store, router: router)
            .sheet(isPresented: $router.showShortcuts) { ShortcutsSheet() }
    }
}

/// The window's layout: onboarding (no sidebar), or the sidebar beside the section. `onboarding` lets snapshot
/// rendering supply a fixture model; the app leaves it nil.
struct WindowScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var router: WindowRouter
    var onboarding: OnboardingModel?
    /// Snapshot rendering only: the plane whose Approach drawer is open at first draw.
    var approachOpen: String?
    /// Snapshot rendering only: the Settings search at first draw.
    var settingsQuery = ""
    /// Snapshot rendering only: the call whose Edit sheet is open at first draw, by `NeedsItem.id`.
    var callOpen: String?
    /// Snapshot rendering only: the split need whose builder is open at first draw, by `NeedsItem.id`.
    var splitOpen: String?

    var body: some View {
        Group {
            if router.showOnboarding {
                // Onboarding has no sidebar: the rail and the pane fill the window.
                OnboardingView(store: store, model: onboarding)
            } else {
                HStack(spacing: 0) {
                    // The sidebar keeps its width whatever the canvas asks for, so no section moves it.
                    Sidebar(router: router, store: store)
                        .layoutPriority(1)
                    canvas
                        .clipped()
                }
            }
        }
        .frame(minWidth: WinMetrics.minWidth, minHeight: WinMetrics.minHeight)
        .background(Gotham.void.ignoresSafeArea())
    }

    private var canvas: some View {
        Group {
            switch router.section {
            case .now:
                NowView(store: store)
            case .approach:
                ApproachSectionView(store: store, opened: approachOpen, editing: callOpen, splitting: splitOpen)
            case .reviews:
                HistoryView(store: store)
            case .repos:
                ReposView(store: store)
            case .schedule:
                ScheduleView(store: store)
            case .settings:
                // Settings lays out its own title row and scrolls as one column.
                SettingsView(store: store, query: settingsQuery)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: router.section)
    }
}

/// The main window, built by AppKit rather than a SwiftUI scene, so it opens from anywhere (the status item, the Dock,
/// launch) without SwiftUI's `openWindow`. Opaque, dark, with the title bar hidden over the void background and the
/// frame autosaved.
@MainActor
enum MainWindow {
    static let title = "Glidepath"
    static let autosaveName = "GlidepathMain"

    static func make(store: Store, router: WindowRouter) -> NSWindow {
        let host = NSHostingController(rootView: MainWindowView(store: store, router: router))
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: WinMetrics.windowWidth, height: WinMetrics.windowHeight),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = host
        // Setting the controller sizes the window to the view; the default size is set after it.
        window.setContentSize(NSSize(width: WinMetrics.windowWidth, height: WinMetrics.windowHeight))
        window.contentMinSize = NSSize(width: WinMetrics.minWidth, height: WinMetrics.minHeight)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = NSColor(Gotham.void)
        window.appearance = NSAppearance(named: .darkAqua)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName(autosaveName) { window.center() }
        window.setFrameAutosaveName(autosaveName)
        return window
    }
}

/// Switches the app between a menu bar app (accessory) and a regular app while the main window is open.
@MainActor
final class MainWindowLifecycle {
    static let shared = MainWindowLifecycle()
    private var closeObserver: NSObjectProtocol?

    /// The main window is about to show: show in the Dock so it can come to front. Watches for its close once.
    func opening(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in
                ScheduleModel.flushLive(Store.shared)
                // Back to a menu bar app, unless the window was opened again in the meantime.
                if !window.isVisible { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}
