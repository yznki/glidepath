import AppKit
import UserNotifications

/// Sweep notifications. Best effort: when permission is denied or a request fails, the failure is logged once and
/// the app carries on. Clicking a notification opens the popover.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Asked once per app version, so the first launch after an update prompts again.
    static let askedKey = "notificationsAskedFor"

    private let paths = Paths()
    private var loggedFailure = false

    /// Installs the delegate, and asks for permission on the first launch of each version.
    static func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        guard UserDefaults.standard.string(forKey: askedKey) != Version.current else { return }
        UserDefaults.standard.set(Version.current, forKey: askedKey)
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                shared.logOnce("notifications: \(error.localizedDescription)")
            } else if !granted {
                shared.logOnce("notifications: permission not granted; sweep results will not notify")
            }
        }
    }

    /// One notification per sweep: the identifier is the run's, so a repeat replaces rather than stacks.
    static func post(_ notice: SweepNotice, runID: String) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        let request = UNNotificationRequest(identifier: "sweep-\(runID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { shared.logOnce("notification: \(error.localizedDescription)") }
        }
    }

    private func logOnce(_ text: String) {
        guard !loggedFailure else { return }
        loggedFailure = true
        Updates.log(text, paths)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { Notifier.openPopover() }
        completionHandler()
    }

    /// Opens the popover by clicking the menu bar item, as the user would. The status item has no public API, so
    /// this finds the button in its window. If the window is not found, the app is at least brought forward.
    static func openPopover() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = firstButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let button = firstButton(in: subview) { return button }
        }
        return nil
    }
}
