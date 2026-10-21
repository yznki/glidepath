import SwiftUI
import AppKit

/// The main window: sidebar beside the canvas. Overview and Reviews are built; other section bodies are placeholders
/// until their phases land.
struct MainWindowView: View {
    @ObservedObject var router = WindowRouter.shared
    @ObservedObject var store = Store.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(router: router)
            canvas
        }
        .frame(minWidth: WinMetrics.minWidth, minHeight: WinMetrics.minHeight)
        .background(WinTheme.ground)
        .background(WindowAccessor())
        .onAppear { MainWindowLifecycle.shared.windowAppeared() }
    }

    private var canvas: some View {
        Group {
            if router.section == .reviews {
                // Reviews is master-detail and runs edge to edge, so it lays out its own insets.
                ReviewsView(store: store)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if router.section == .overview {
                        // The hero starts on the title line, so Overview has no title row of its own.
                        OverviewView(store: store)
                    } else {
                        Text(router.section.title)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(WinTheme.text)
                            .frame(height: 32, alignment: .leading)
                            .id(router.section)
                            .transition(.opacity)
                        Spacer(minLength: 0)
                    }
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { WindowRouter.shared.openAction = { id in openWindow(id: id) } }
    }
}
