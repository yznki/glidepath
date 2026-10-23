import SwiftUI
import AppKit

/// The sections of the main window, in sidebar order.
enum WindowSection: String, CaseIterable {
    case now, reviews, repos, schedule, settings

    var title: String {
        switch self {
        case .now: return "Now"
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

    @Published var section: WindowSection = .now
    /// A review the Now rows asked Reviews to select, by `Strip.id`. Reviews takes it when it appears.
    @Published var reviewFocus: String?
    /// The window shows onboarding instead of the sections. Set while there is no config file, and by the popover's
    /// "Set up Glidepath…". Cleared when onboarding finishes.
    @Published var showOnboarding: Bool
    var openAction: ((String) -> Void)?
    /// The ⌘/ sheet.
    @Published var showShortcuts = false
    /// An action a view must carry out (filters, Add Repo, the review actions). The view that owns it takes it.
    @Published var pending: ShortcutAction?
    private var launchChecked = false

    /// Defaults to onboarding while there is no config file.
    init(section: WindowSection = .now, showOnboarding: Bool? = nil) {
        self.section = section
        self.showOnboarding = showOnboarding ?? WindowRouter.needsSetup()
    }

    /// True when the window should open on onboarding: config.toml is missing or has no repos, or (when the window is
    /// opened without a section, from the popover's setup or at launch) a first sweep failed and has not been retried.
    /// A section opened from elsewhere, such as Reviews, never opens onboarding for a failed sweep.
    static func needsSetup(paths: Paths = Paths(), forSection: Bool = false) -> Bool {
        opensOnboarding(configured: isConfigured(paths),
                        failedSweep: OnboardingResume.failedSweep != nil, forSection: forSection)
    }

    /// config.toml parses and lists at least one repo.
    static func isConfigured(_ paths: Paths) -> Bool {
        ((try? Config.load(paths))?.repos.isEmpty ?? true) == false
    }

    /// The decision behind `needsSetup`, without the disk or the failure state.
    nonisolated static func opensOnboarding(configured: Bool, failedSweep: Bool, forSection: Bool) -> Bool {
        !configured || (!forSection && failedSweep)
    }

    /// Selects `section` (when given), opens the main window and brings the app forward. With no config file the
    /// window opens on onboarding.
    func open(_ section: WindowSection?) {
        if let section { self.section = section }
        if WindowRouter.needsSetup(forSection: section != nil) { showOnboarding = true }
        // Regular first, so the window can come to front over other apps while the Dock icon is shown.
        NSApp.setActivationPolicy(.regular)
        openAction?("main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens Reviews with the PR `stripID` selected.
    func openReview(_ stripID: String) {
        reviewFocus = stripID
        open(.reviews)
    }

    /// Hands a view-owned action to the view. Selects `section` first when given.
    func deliver(_ action: ShortcutAction, section: WindowSection?) {
        if let section { self.section = section }
        pending = action
    }

    /// The pending action, when it is one of `actions`. Taking it clears it.
    func take(_ actions: Set<ShortcutAction>) -> ShortcutAction? {
        guard let p = pending, actions.contains(p) else { return nil }
        pending = nil
        return p
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
