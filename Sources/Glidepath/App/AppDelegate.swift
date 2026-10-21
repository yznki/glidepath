import AppKit

/// Quitting waits for a pending schedule save, so a nudge made just before ⌘Q is written. The wait is capped at 5 s,
/// so a stuck write cannot hold the app open.
final class GlidepathAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = ScheduleModel.live, model.hasPendingSave else { return .terminateNow }
        Task { @MainActor in
            await model.flushAndWait(Store.shared, timeout: 5)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
