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
    /// A reviewer's thread or comment that Glidepath disagrees with.
    case disagree
    /// A thread whose reply Glidepath cannot settle alone.
    case unclear
    /// A fix whose session reported low confidence.
    case lowConfidence
    /// Merging a ready PR.
    case land
    /// Pushing a conflict resolution the session was not confident in.
    case conflict
    /// Reverting a landed PR that broke main.
    case revert
}

enum Autopilot {
    /// Hard stops (give up, flagged paths, a limit, a refused push) always go to the user. A fix on an approved PR is
    /// pushed by Glidepath only when autopilot is on or pushing always is set. Everything else is Glidepath's.
    /// With autopilot on, a call Glidepath would hand to the user goes to the council first. Disagreeing acts alone
    /// when the config says reply and resolve.
    /// Landing acts under autopilot or `merge = "auto"`, and waits for the user under `ask`. With `off` it never acts.
    static func actor(_ action: TendAction, autopilot: Bool, push: TendPush, disagree: TendDisagree = .draft,
                      merge: TendMerge = .off) -> Actor {
        switch action {
        case .rerun, .pushFix(approved: false): return .act
        case .pushFix(approved: true): return (autopilot || push == .always) ? .act : .you
        case .giveUp, .flagPaths, .limitHit, .guardRefused: return .you
        case .disagree:
            if autopilot { return .council }
            return disagree == .replyResolve ? .act : .you
        case .unclear, .lowConfidence: return autopilot ? .council : .you
        case .land:
            if merge == .off { return .you }
            return (autopilot || merge == .auto) ? .act : .you
        case .conflict, .revert: return autopilot ? .council : .you
        }
    }
}
