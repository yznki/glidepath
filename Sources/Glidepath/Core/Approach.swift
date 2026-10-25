import Foundation

/// A PR as the approach view reads it: one row of the GraphQL search, with the checks, threads and reviews it needs.
struct OpenPR: Codable, Equatable {
    var n = 0
    var title = ""
    var body = ""
    var url = ""
    var author = ""
    var isDraft = false
    var isFork = false
    var labels: [String] = []
    var reviewDecision: String?
    var mergeable: String?
    var mergeStateStatus: String?
    var branch = ""
    var head = ""
    var base = ""
    var additions = 0
    var deletions = 0
    var checks: [CheckState] = []
    var threads: [ReviewThread] = []
    var reviews: [ReviewInfo] = []
    var requested: [String] = []
    var updatedAt: Date?
}

/// One check run or commit status. `conclusion` is nil while the check runs.
struct CheckState: Codable, Equatable {
    var name: String
    var status: String
    var conclusion: String?
    var url: String?
}

struct ReviewThread: Codable, Equatable {
    var id: String
    var isResolved: Bool
    var comments: [ThreadComment]
}

struct ThreadComment: Codable, Equatable {
    var id: String
    var databaseId: Int?
    var author: String
    var body: String
    var path: String?
    var line: Int?
}

struct ReviewInfo: Codable, Equatable {
    var id: String
    var author: String
    /// APPROVED, CHANGES_REQUESTED, COMMENTED or DISMISSED.
    var state: String
}

enum CIStatus: String, Codable, Equatable { case none, pending, failed, passed }

extension OpenPR {
    static let failureConclusions: Set<String> = ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED",
                                                  "STARTUP_FAILURE", "ERROR"]

    /// No checks is `none`. Any check still running is `pending`, checked before failures. Any failed conclusion is
    /// `failed`; the rest is `passed`.
    var ciStatus: CIStatus {
        if checks.isEmpty { return .none }
        if checks.contains(where: { $0.status != "COMPLETED" }) { return .pending }
        if !failedChecks.isEmpty { return .failed }
        return .passed
    }

    /// Every check that concluded in a failure.
    /// ponytail: every check counts as required; a PR's optional red check is still fixed.
    var failedChecks: [CheckState] {
        checks.filter { OpenPR.failureConclusions.contains($0.conclusion ?? "") }
    }
}

enum ApproachPhase: String, Codable, Equatable { case taxiing, flying, waiting, holding, cleared, landed }

/// Whether a gate is passed (ok), waiting on someone else (wait), needs work (work), or does not apply (none).
enum GateState: String, Codable, Equatable { case ok, wait, work, none }

struct Gate: Codable, Equatable {
    var name: String
    var state: GateState
    var detail: String
    var who: String?
}

/// One PR's place in the approach chart.
struct ApproachPlane: Codable, Equatable {
    var slug: String
    var n: Int
    var title: String
    var url: String
    var phase: ApproachPhase
    var marker: Int
    var label: String
    var waitingOn: String?
    var lane: Int
    /// 1 for the bottom of a stack, counting up. nil for a PR that stands alone.
    var stackIndex: Int?
    var off: Bool
    var gates: [Gate]
    var ci: String
}

/// A thing the user must decide: a held fix, or a stuck PR. `kind` is "held" or "stuck".
struct NeedsItem: Codable, Equatable {
    var id: String
    var slug: String
    var n: Int
    var title: String
    var kind: String
    var detail: String
}

/// What the approach view and the menu bar read from `stateDir/tend/approach.json`.
struct ApproachSnapshot: Codable, Equatable {
    var updated: Date
    var planes: [ApproachPlane]
    var needs: [NeedsItem]
    var queued: Int
    var status: String?
    var working: String?
    var nextLook: Date?
}

enum Approach {
    static let handsOffLabel = "glidepath:hands-off"

    /// How far a PR has got. 1: CI passed (or none). 2: approved, no change request, no open thread. 3: also clean
    /// and not a draft. 0 while CI is pending or failing. Landed (4) is set by the landing step, not here.
    static func marker(_ pr: OpenPR) -> Int {
        guard pr.ciStatus == .passed || pr.ciStatus == .none else { return 0 }
        guard pr.reviewDecision == "APPROVED", !pr.reviews.contains(where: { $0.state == "CHANGES_REQUESTED" }),
              !pr.threads.contains(where: { !$0.isResolved }) else { return 1 }
        guard pr.mergeStateStatus == "CLEAN", !pr.isDraft else { return 2 }
        return 3
    }

    static func phase(_ pr: OpenPR, state: TendPR?, working: Bool) -> ApproachPhase {
        if pr.isDraft { return .taxiing }
        if state?.held != nil || state?.stuck != nil { return .holding }
        if working || (pr.ciStatus == .failed && tendable(pr, state)) { return .flying }
        return marker(pr) == 3 ? .cleared : .waiting
    }

    /// The checks, reviews, threads and readiness, each as a gate. A failing CI gate names Glidepath as the one
    /// working on it when tending may act on the PR.
    static func gates(_ pr: OpenPR, state: TendPR?) -> [Gate] {
        let ci: Gate
        switch pr.ciStatus {
        case .none: ci = Gate(name: "CI", state: .none, detail: "No checks")
        case .pending: ci = Gate(name: "CI", state: .wait, detail: "Running")
        case .passed: ci = Gate(name: "CI", state: .ok, detail: "Passed")
        case .failed:
            ci = Gate(name: "CI", state: .work, detail: pr.failedChecks.map(\.name).joined(separator: ", "),
                      who: tendable(pr, state) ? "Glidepath" : nil)
        }
        let open = pr.threads.filter { !$0.isResolved }
        let threads = open.isEmpty ? Gate(name: "Threads", state: .ok, detail: "All resolved")
            : Gate(name: "Threads", state: .work, detail: "\(open.count) open", who: open.first?.comments.first?.author)
        let approval: Gate
        if pr.reviewDecision == "APPROVED" {
            approval = Gate(name: "Approval", state: .ok, detail: "Approved")
        } else if let changes = pr.reviews.first(where: { $0.state == "CHANGES_REQUESTED" }) {
            approval = Gate(name: "Approval", state: .work, detail: "Changes requested", who: changes.author)
        } else {
            approval = Gate(name: "Approval", state: .wait, detail: "Needs approval", who: pr.requested.first)
        }
        let ready: Gate
        if pr.isDraft {
            ready = Gate(name: "Ready", state: .none, detail: "Draft")
        } else if pr.mergeStateStatus == "CLEAN" {
            ready = Gate(name: "Ready", state: .ok, detail: "Clean")
        } else {
            ready = Gate(name: "Ready", state: .wait, detail: pr.mergeStateStatus?.lowercased() ?? "Unknown")
        }
        return [ci, threads, approval, ready]
    }

    /// The one line the approach view shows for a PR. `triesPerHead` is the config's limit, for "try k of N".
    static func label(_ pr: OpenPR, state: TendPR?, working: Bool,
                      triesPerHead: Int = TendConfig().triesPerHead) -> String {
        if pr.isDraft { return "Draft" }
        if let held = state?.held { return "Fix held · \(held.summary)" }
        if let stuck = state?.stuck { return "Stuck · \(stuck)" }
        if working {
            let tries = min((state?.triesByHead[pr.head] ?? 0) + 1, triesPerHead)
            return "Glidepath fixing \(pr.failedChecks.first?.name ?? "CI") · try \(tries) of \(triesPerHead)"
        }
        if marker(pr) == 3 { return "Ready to land" }
        if pr.ciStatus == .pending { return "Waiting on CI" }
        if pr.ciStatus == .failed, !tendable(pr, state) { return "Hands off · checks failing" }
        if pr.ciStatus == .failed { return "Checks failing · \(pr.failedChecks.map(\.name).joined(separator: ", "))" }
        if let who = waitingOn(pr) { return "Waiting on \(who)" }
        return "Waiting on review"
    }

    /// The reviewer the PR waits on: the first one GitHub still asks for. Nil once approved.
    static func waitingOn(_ pr: OpenPR) -> String? {
        pr.reviewDecision == "APPROVED" ? nil : pr.requested.first
    }

    /// Stacks: a PR whose base is another open PR's branch sits on it. A lane runs bottom-up from a root (a PR whose
    /// base is no open branch). Lanes are ordered by their first PR's number.
    static func lanes(_ prs: [OpenPR]) -> [[OpenPR]] {
        let branches = Set(prs.map(\.branch))
        var lanes: [[OpenPR]] = []
        var placed = Set<Int>()
        for root in prs.filter({ !branches.contains($0.base) }).sorted(by: { $0.n < $1.n }) {
            var lane = [root]
            placed.insert(root.n)
            // ponytail: a branch with two children continues into the lower-numbered one; the other gets a lane of its own.
            while let child = prs.filter({ $0.base == lane[lane.count - 1].branch && !placed.contains($0.n) })
                .min(by: { $0.n < $1.n }) {
                lane.append(child)
                placed.insert(child.n)
            }
            lanes.append(lane)
        }
        // A cycle of PRs, each based on another, has no root. Each of them gets a lane of its own.
        for pr in prs where !placed.contains(pr.n) { lanes.append([pr]) }
        return lanes.sorted { $0[0].n < $1[0].n }
    }

    static func plane(_ pr: OpenPR, slug: String, state: TendPR?, working: Bool, lane: Int, stackIndex: Int?,
                      triesPerHead: Int = TendConfig().triesPerHead) -> ApproachPlane {
        ApproachPlane(slug: slug, n: pr.n, title: pr.title, url: pr.url,
                      phase: phase(pr, state: state, working: working), marker: marker(pr),
                      label: label(pr, state: state, working: working, triesPerHead: triesPerHead),
                      waitingOn: waitingOn(pr), lane: lane, stackIndex: stackIndex,
                      off: !tendable(pr, state), gates: gates(pr, state: state), ci: pr.ciStatus.rawValue)
    }

    /// The Needs item for a PR: a held fix, or a stuck PR. A held fix is listed first. Nil when neither.
    static func needs(_ slug: String, _ pr: OpenPR, state: TendPR?) -> NeedsItem? {
        func item(_ kind: String, _ detail: String) -> NeedsItem {
            NeedsItem(id: "\(slug)#\(pr.n)/\(kind)", slug: slug, n: pr.n, title: pr.title, kind: kind, detail: detail)
        }
        if let held = state?.held { return item("held", "Fix held · \(held.summary)") }
        if let stuck = state?.stuck { return item("stuck", stuck) }
        return nil
    }

    /// Tending may act on the PR: it is not switched off and not marked hands-off.
    static func tendable(_ pr: OpenPR, _ state: TendPR?) -> Bool {
        !(state?.off ?? false) && !pr.labels.contains(handsOffLabel)
    }
}
