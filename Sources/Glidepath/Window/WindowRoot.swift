import SwiftUI
import AppKit

/// The sections of the main window, in sidebar order.
enum WindowSection: String, CaseIterable {
    case overview, reviews, repos, schedule, settings

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .reviews: return "Reviews"
        case .repos: return "Repos"
        case .schedule: return "Schedule"
        case .settings: return "Settings"
        }
    }
}

/// Holds the section the main window shows and opens the window from anywhere. `openAction` is set by a view
/// inside the menu bar scene, because only a view can reach `openWindow`.
@MainActor
final class WindowRouter: ObservableObject {
    static let shared = WindowRouter()

    @Published var section: WindowSection = .overview
    /// The window shows onboarding instead of the sections. Set while there is no config file, and by the popover's
    /// "Set up Glidepath…". Cleared when onboarding finishes.
    @Published var showOnboarding = WindowRouter.needsSetup()
    var openAction: ((String) -> Void)?
    private var launchChecked = false

    /// True when there is no config file yet, so the window opens on onboarding.
    static func needsSetup(paths: Paths = Paths()) -> Bool {
        !FileManager.default.fileExists(atPath: paths.configFile)
    }

    /// Selects `section` (when given), opens the main window and brings the app forward. With no config file the
    /// window opens on onboarding.
    func open(_ section: WindowSection?) {
        if let section { self.section = section }
        if WindowRouter.needsSetup() { showOnboarding = true }
        openAction?("main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The popover's "Set up Glidepath…": opens the window on onboarding.
    func openOnboarding() {
        showOnboarding = true
        open(nil)
    }

    /// Called once per launch from the menu bar label: opens the window only when there is no config file, so an
    /// existing setup does not get a window on every launch.
    func openAtLaunchIfUnconfigured() {
        guard !launchChecked else { return }
        launchChecked = true
        guard WindowRouter.needsSetup() else { return }
        open(nil)
    }
}
