import SwiftUI
import AppKit

/// The main window: sidebar beside the canvas. Every section is built. The window's AppKit hooks live here; the layout
/// is in `WindowScreen`, which snapshot rendering draws on its own.
struct MainWindowView: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var store: Store

    init(store: Store? = nil, router: WindowRouter? = nil) {
        self.store = store ?? Store.shared
        self.router = router ?? WindowRouter.shared
    }

    var body: some View {
        WindowScreen(store: store, router: router)
            .background(WindowAccessor())
            .onAppear { MainWindowLifecycle.shared.windowAppeared() }
    }
}

/// The window's layout: onboarding (no sidebar), or the sidebar beside the section. `onboarding` lets snapshot
/// rendering supply a fixture model; the app leaves it nil.
struct WindowScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var router: WindowRouter
    var onboarding: OnboardingModel?

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
        .background(WinTheme.ground)
    }

    private var canvas: some View {
        Group {
            if router.section == .reviews {
                // Reviews is master-detail and runs edge to edge, so it lays out its own insets.
                ReviewsView(store: store)
            } else if router.section == .repos {
                // Repos is master-detail too, with the same edge-to-edge layout.
                ReposView(store: store)
            } else if router.section == .schedule {
                ScheduleView(store: store)
            } else if router.section == .settings {
                // Settings lays out its own title row and scrolls as one column.
                SettingsView(store: store)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // The hero starts on the title line, so Overview has no title row of its own.
                    OverviewView(store: store)
                }
                .padding(.leading, WinMetrics.canvasLeft)
                .padding(.trailing, WinMetrics.canvasRight)
                .padding(.top, WinMetrics.canvasTop)
                .padding(.bottom, WinMetrics.canvasBottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: router.section)
    }
}

/// Gives the main window a frame autosave name, so it remembers its size and place.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.setFrameAutosaveName("GlidepathMain") }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Switches the app between a menu bar app (accessory) and a regular app while the main window is open.
@MainActor
final class MainWindowLifecycle {
    static let shared = MainWindowLifecycle()
    private var closeObserver: NSObjectProtocol?

    /// The main window appeared: show in the Dock and bring the app forward. Watches for its close once.
    func windowAppeared() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard (note.object as? NSWindow)?.title == "Glidepath" else { return }
            Task { @MainActor [weak self] in self?.settle() }
        }
    }

    /// Runs after a close. Back to a menu bar app once no main window is still visible.
    private func settle() {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.title == "Glidepath" }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Lives in the menu bar scene, where `openWindow` is available, and hands the router a way to open the window.
struct OpenWindowBridge: View {
    /// Only the menu bar label sets this: it is on screen from launch, so it opens the window once when no config exists.
    var opensWhenUnconfigured = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowRouter.shared.openAction = { id in openWindow(id: id) }
                if opensWhenUnconfigured { WindowRouter.shared.openAtLaunchIfUnconfigured() }
            }
    }
}
