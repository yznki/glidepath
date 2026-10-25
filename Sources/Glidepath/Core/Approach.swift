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
    /// The repo's default branch, what `base` must be for the PR to land. "" when GitHub did not say.
    var defaultBranch = ""
    var additions = 0
    var deletions = 0
    var checks: [CheckState] = []
    var threads: [ReviewThread] = []
    var reviews: [ReviewInfo] = []
    var requested: [String] = []
    var updatedAt: Date?
    /// Plain PR comments (issue comments), not review threads.
    var comments: [PRComment] = []
}

/// A plain comment on the PR conversation.
struct PRComment: Codable, Equatable {
    var id: String
    var databaseId: Int?
    var author: String
    var body: String
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
    var body: String = ""
    var databaseId: Int?
}

enum CIStatus: String, Codable, Equatable { case none, pending, failed, passed }

extension OpenPR {
    /// Approved: GitHub's decision says so. With no decision (no branch rule asks for reviews), each author's latest
    /// review is an approval or a change request, and at least one approves and none requests changes.
    var approved: Bool {
        if reviewDecision == "APPROVED" { return true }
        guard reviewDecision == nil else { return false }
        var latest: [String: String] = [:]
        for review in reviews where review.state == "APPROVED" || review.state == "CHANGES_REQUESTED" {
            latest[review.author] = review.state
        }
        return latest.values.contains("APPROVED") && !latest.values.contains("CHANGES_REQUESTED")
    }

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

/// A gate's state: passed (ok), waiting on a person or GitHub (wait), Glidepath acting now (work), or not reached (none).
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
    /// When a landed PR merged. nil for a PR that has not landed (and for files from before 1.8).
    var landedAt: Date?
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
        guard pr.approved, !pr.reviews.contains(where: { $0.state == "CHANGES_REQUESTED" }),
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

    /// The checks, reviews, threads and readiness, each as a gate, in words. `work` is Glidepath acting now: a failing
    /// CI on a PR tend may act on, and not stuck or held. A gate that waits on someone names them in `who`: the
    /// reviewers, or "you" when the PR is stuck or held.
    static func gates(_ pr: OpenPR, state: TendPR?) -> [Gate] {
        let mine = state?.held != nil || state?.stuck != nil
        func person(_ named: String?) -> String? { mine ? "you" : named }
        let ci: Gate
        switch pr.ciStatus {
        case .none:
            ci = Gate(name: "CI", state: .none, detail: "No checks")
        case .pending:
            let running = pr.checks.filter { $0.status != "COMPLETED" }.count
            ci = Gate(name: "CI", state: .wait, detail: "\(running) running", who: person(nil))
        case .passed:
            let green = pr.checks.filter { ["SUCCESS", "NEUTRAL", "SKIPPED"].contains($0.conclusion ?? "") }.count
            ci = Gate(name: "CI", state: .ok, detail: "\(green) of \(pr.checks.count) checks green")
        case .failed:
            let failing = pr.failedChecks.map(\.name).joined(separator: ", ")
            if tendable(pr, state) && !mine {
                ci = Gate(name: "CI", state: .work, detail: "\(failing) failing", who: "Glidepath")
            } else {
                ci = Gate(name: "CI", state: .wait, detail: "\(failing) failing", who: "you")
            }
        }
        let open = pr.threads.filter { !$0.isResolved }
        let calls = state?.calls ?? []
        let threads: Gate
        if !calls.isEmpty {
            threads = Gate(name: "Threads", state: .wait, detail: "\(open.count) open · \(calls.count) need your call",
                           who: "you")
        } else if open.isEmpty {
            threads = Gate(name: "Threads", state: .ok, detail: "All resolved")
        } else {
            threads = Gate(name: "Threads", state: .wait, detail: "\(open.count) open",
                           who: person(open.first?.comments.first?.author))
        }
        let approval: Gate
        if pr.approved {
            approval = Gate(name: "Approval", state: .ok, detail: "Approved")
        } else if let changes = pr.reviews.first(where: { $0.state == "CHANGES_REQUESTED" }) {
            approval = Gate(name: "Approval", state: .wait, detail: "Changes requested by \(changes.author)",
                            who: person(changes.author))
        } else if !pr.requested.isEmpty {
            let reviewers = pr.requested.joined(separator: ", ")
            approval = Gate(name: "Approval", state: .wait, detail: "Waiting on \(reviewers)", who: person(reviewers))
        } else {
            approval = Gate(name: "Approval", state: .wait, detail: "No review yet", who: person(nil))
        }
        let ready: Gate
        let base = pr.base
        if pr.isDraft || pr.mergeStateStatus == "DRAFT" {
            ready = Gate(name: "Ready", state: .none, detail: "Draft")
        } else {
            switch pr.mergeStateStatus {
            case "CLEAN": ready = Gate(name: "Ready", state: .ok, detail: "No conflicts with \(base)")
            case "DIRTY": ready = Gate(name: "Ready", state: .wait, detail: "Conflicts with \(base)", who: person(nil))
            case "BEHIND": ready = Gate(name: "Ready", state: .wait, detail: "Behind \(base)", who: person(nil))
            case "BLOCKED": ready = Gate(name: "Ready", state: .wait, detail: "Blocked by branch rules", who: person(nil))
            case "UNSTABLE": ready = Gate(name: "Ready", state: .wait, detail: "Checks not all green", who: person(nil))
            default: ready = Gate(name: "Ready", state: .wait, detail: "Waiting on GitHub", who: person(nil))
            }
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
        pr.approved ? nil : pr.requested.first
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

    /// The Needs items for a PR: a held fix or a stuck PR first, then one per comment the user must answer. Empty when
    /// none.
    /// `landable` is set when the PR is ready and the merge setting is `ask`; `prs` names the stack above it.
    static func needs(_ slug: String, _ pr: OpenPR, state: TendPR?, landable: Bool = false,
                      prs: [OpenPR] = []) -> [NeedsItem] {
        func item(_ id: String, _ kind: String, _ detail: String) -> NeedsItem {
            NeedsItem(id: "\(slug)#\(pr.n)/\(id)", slug: slug, n: pr.n, title: pr.title, kind: kind, detail: detail)
        }
        var items: [NeedsItem] = []
        if let held = state?.held {
            items.append(item("held", "held", "Fix held · \(held.summary)"))
        } else if let stuck = state?.stuck {
            items.append(item("stuck", "stuck", stuck))
        }
        for call in state?.calls ?? [] {
            let detail = "Your call · \(call.author): \"\(call.quote)\"" + (call.draft != nil ? " · draft reply ready" : "")
            items.append(item(call.id, "call", detail))
        }
        if landable {
            items.append(item("land", "land", Landing.detail(pr, prs)))
        }
        return items
    }

    /// Tending may act on the PR: it is not switched off and not marked hands-off.
    static func tendable(_ pr: OpenPR, _ state: TendPR?) -> Bool {
        !(state?.off ?? false) && !pr.labels.contains(handsOffLabel)
    }
}
