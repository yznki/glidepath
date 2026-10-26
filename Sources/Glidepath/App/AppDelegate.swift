import AppKit
import Combine

/// Quitting waits for a pending schedule save, so a nudge made just before ⌘Q is written. The wait is capped at 5 s,
/// so a stuck write cannot hold the app open. The Dock icon shows only while the main window is open (MainWindowLifecycle
/// switches the activation policy). Closing the window keeps the app running in the menu bar.
@MainActor
final class GlidepathAppDelegate: NSObject, NSApplicationDelegate {
    private var badgeSink: AnyCancellable?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        badgeSink = Store.shared.$needsYou.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateBadge() }
        updateBadge()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBar.install()
        WindowRouter.shared.openAtLaunchIfUnconfigured()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = ScheduleModel.live, model.hasPendingSave else { return .terminateNow }
        Task { @MainActor in
            await model.flushAndWait(Store.shared, timeout: 5)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A Dock click, or a second launch from Finder, Spotlight or Launchpad, opens or fronts the main window. False,
    /// so AppKit and SwiftUI do nothing more.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowRouter.shared.open(nil)
        return false
    }

    /// Check now, Pause and Open, the same items as the menu bar's right-click menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MenuBar.shared?.menu(full: false)
    }

    /// The Needs-you count on the Dock icon. Nil (no badge) when nothing needs the user.
    private func updateBadge() {
        let count = Store.shared.needsCount
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
