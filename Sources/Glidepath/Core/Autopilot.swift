import Foundation

/// Who takes a tend step: Glidepath alone, a second opinion first, or the user.
enum Actor: String, Equatable { case act, council, you }

/// A step tend may take on a PR.
enum TendAction: Equatable {
    case pushFix(approved: Bool)
    case rerun
    case giveUp
    case flagPaths
    case limitHit
    case guardRefused
}

enum Autopilot {
    /// Hard stops (give up, flagged paths, a limit, a refused push) always go to the user. A fix on an approved PR is
    /// pushed by Glidepath only when autopilot is on or pushing always is set. Everything else is Glidepath's.
    /// ponytail: `council` is not returned yet; the second-opinion step is added with its budget.
    static func actor(_ action: TendAction, autopilot: Bool, push: TendPush) -> Actor {
        switch action {
        case .rerun, .pushFix(approved: false): return .act
        case .pushFix(approved: true): return (autopilot || push == .always) ? .act : .you
        case .giveUp, .flagPaths, .limitHit, .guardRefused: return .you
        }
    }
}
