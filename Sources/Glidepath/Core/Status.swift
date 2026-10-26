import Foundation

/// How far a running check has got. `total` is zero while the runner is still listing PRs, and for work on the user's
/// own PRs, which has no count.
struct CheckProgress: Equatable {
    var done = 0
    var total = 0
    /// The repo being checked, when the check covers one.
    var repo: String?
    /// The work is on the user's own PRs, not a review of team PRs.
    var yourPRs = false

    /// 0 to 1, or nil when there is nothing to count yet.
    var fraction: Double? { total > 0 ? Double(done) / Double(total) : nil }
}

/// Why Glidepath holds work back on its own, as opposed to a pause the user chose.
enum HoldReason: Equatable {
    /// Heavy work waits for quiet hours.
    case quietHours
    /// The Claude usage passed what the reserve leaves; `reserve` is the percent kept for the user.
    case usageReserve(reserve: Int)
}

/// The button that clears a problem.
enum FixAction: Equatable {
    case setUp, installSchedule, signIn, showLog
}

/// What is broken. Each one names its fix.
enum ProblemReason: Equatable {
    /// No repos in the config.
    case notSetUp
    /// The launchd job is missing.
    case notScheduled
    /// Reinstalling the launchd job failed, with the error.
    case scheduleFailed(String)
    /// GitHub refused the sign-in.
    case signedOut
    /// The last check failed, with the error in plain words.
    case checkFailed(String)

    var fix: FixAction {
        switch self {
        case .notSetUp: return .setUp
        case .notScheduled, .scheduleFailed: return .installSchedule
        case .signedOut: return .signIn
        case .checkFailed: return .showLog
        }
    }
}

/// The one state the glide line, the menu bar icon and the status sentence show.
enum GlideState: Equatable {
    case quiet(next: Date?)
    case checking(CheckProgress)
    case needs(count: Int)
    case problem(reason: ProblemReason, fix: FixAction)
    case paused(until: Date?)
    case holdingBack(reason: HoldReason, resumesAt: Date?)

    /// Setup problems first, then the user's pause, then a running check, then a failed check, then what needs the user,
    /// then work held back, then quiet. A running check hides the last check's failure: it is about to be replaced.
    static func derive(_ snap: Snapshot, needs: Int, jobError: String? = nil) -> GlideState {
        if snap.repoCount == 0 { return problem(.notSetUp) }
        if !snap.jobInstalled { return problem(.notScheduled) }
        if let jobError { return problem(.scheduleFailed(jobError)) }
        if snap.paused { return .paused(until: snap.pausedUntil) }
        if let progress = checking(snap) { return .checking(progress) }
        if let run = snap.run, run.finished != nil, let message = Presentation.failureMessage(run) {
            return problem(signedOut(message) ? .signedOut : .checkFailed(Presentation.plainFailure(message)))
        }
        if needs > 0 { return .needs(count: needs) }
        if snap.tendOn, !snap.queue.isEmpty {
            let usage = snap.queue.filter { $0.reason != UsageGuard.quietReason }
            let reserve = snap.usage?.reserve ?? snap.config?.tend.usageReserve ?? TendConfig().usageReserve
            let held = usage.isEmpty ? snap.queue : usage
            return .holdingBack(reason: usage.isEmpty ? .quietHours : .usageReserve(reserve: reserve),
                                resumesAt: held.compactMap(\.until).min())
        }
        return .quiet(next: snap.nextRun)
    }

    private static func problem(_ reason: ProblemReason) -> GlideState {
        .problem(reason: reason, fix: reason.fix)
    }

    /// A sweep or dry run with its count, or a tend round at work on one of the user's PRs. A tend check that is only
    /// reading PRs is not shown: it runs every five minutes and would make the line flicker.
    static func checking(_ snap: Snapshot) -> CheckProgress? {
        if let run = snap.running ? snap.run : (snap.dryRunning ? snap.dryRun : nil) {
            let digest = RunDigest(run: run, running: true)
            return CheckProgress(done: digest.done, total: digest.toReview,
                                 repo: run.repos.count == 1 ? run.repos[0].slug : nil)
        }
        if snap.dryRunning { return CheckProgress() }
        if snap.tendRunning, snap.approach?.working != nil { return CheckProgress(yourPRs: true) }
        return nil
    }

    /// The failure reads as a GitHub sign-in problem.
    /// ponytail: matched on gh's words; give the runner an error kind if these drift.
    static func signedOut(_ message: String) -> Bool {
        let m = message.lowercased()
        return ["gh auth login", "authentication", "bad credentials", "http 401"].contains { m.contains($0) }
    }
}

/// What Glidepath did on its own since the user last looked: reviews posted, fixes pushed, PRs merged.
struct SinceLastLooked: Equatable {
    var reviewsPosted = 0
    /// PR numbers, oldest first.
    var fixesPushed: [Int] = []
    var merged: [Int] = []

    var isEmpty: Bool { reviewsPosted == 0 && fixesPushed.isEmpty && merged.isEmpty }

    /// A review counts as posted when it went out with its run (no draft) or the user posted its draft, after `after`.
    /// Dry runs post nothing. A fix counts when a tend round pushed it; a merge when tend merged the PR.
    static func make(runs: [RunState], landed: [TendLanded], after: Date) -> SinceLastLooked {
        var out = SinceLastLooked()
        for run in runs.sorted(by: { $0.started < $1.started }) {
            if run.isTend {
                if run.tendAction == "fixed", run.started >= after, let n = run.repos.first?.prs.first?.n {
                    out.fixesPushed.append(n)
                }
                continue
            }
            guard run.dryRun != true, run.kind != "self-review" else { continue }
            for pr in run.repos.flatMap(\.prs) where pr.carriedFrom == nil && (pr.verdict == .approve || pr.verdict == .changes) {
                if let posted = pr.posted {
                    if posted >= after { out.reviewsPosted += 1 }
                } else if pr.draft == nil, run.started >= after {
                    out.reviewsPosted += 1
                }
            }
        }
        out.merged = landed.filter { $0.at >= after }.sorted { $0.at < $1.at }.map(\.n)
        return out
    }
}
