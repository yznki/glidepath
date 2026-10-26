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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = ScheduleModel.live, model.hasPendingSave else { return .terminateNow }
        Task { @MainActor in
            await model.flushAndWait(Store.shared, timeout: 5)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A Dock click, or a second launch from Finder, Spotlight or Launchpad, opens or fronts the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowRouter.shared.open(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let store = Store.shared
        let menu = NSMenu()
        menu.addItem(item("Open Glidepath", #selector(openWindow)))
        let review = item("Review now", #selector(reviewNow))
        review.isEnabled = !store.snap.running && store.snap.jobInstalled
        menu.addItem(review)
        menu.addItem(item(store.snap.paused ? "Resume" : "Pause", #selector(togglePause)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    @objc private func openWindow() { WindowRouter.shared.open(nil) }

    @objc private func reviewNow() { Confirm.run(Store.shared) }

    @objc private func togglePause() { Store.shared.togglePause() }

    /// The Needs-you count on the Dock icon. Nil (no badge) when nothing needs the user.
    private func updateBadge() {
        let count = Store.shared.needsCount
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
