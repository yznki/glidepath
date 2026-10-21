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
    var openAction: ((String) -> Void)?

    /// Selects `section` (when given), opens the main window and brings the app forward.
    func open(_ section: WindowSection?) {
        if let section { self.section = section }
        openAction?("main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
