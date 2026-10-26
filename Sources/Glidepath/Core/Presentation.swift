import Foundation

/// Which header copy to show (docs/design.md, section 2). Chosen from the snapshot alone, so it is testable.
enum HeaderKind: Equatable {
    case notScheduled
    case paused(since: Date?, lastStarted: Date?)
    case running(changes: Int, reviewing: Int, total: Int, landed: Int, started: Date?)
    /// A sweep is running but has recorded no PRs yet: the runner is still indexing or listing.
    case preparing(phase: String?, started: Date?)
    case failed(reason: String, started: Date?, next: Date?)
    case emptyRun(repos: Int, next: Date?, lastStarted: Date?)
    case idle(changes: Int, next: Date?, lastStarted: Date?, total: Int)
    case notConfigured(next: Date?)
    case noSweeps(next: Date?, repos: Int)
    case dryRun
}

/// The status idiom of a row (docs/design.md, section 3): a shape and a label, one per row.
enum RowStatus: Equatable {
    case changes                       // triangle, "Changes"
    case approved                      // circle, "Approved"
    case skipped(reason: String?)      // dash, "Skipped"
    case noResult                      // hollow circle, "No result"
    case active(phase: String)         // hollow blue circle, the stage word, and a meter
    case queued                        // hollow grey circle, "Queued"
}

/// The notification for a finished sweep. Pure, so the copy is testable.
struct SweepNotice: Equatable {
    let title: String
    let body: String
}

/// One segment of the four-dash meter.
enum MeterSegment: Equatable {
    case done, current, future
}

/// One PR as a row.
struct RowModel: Equatable, Identifiable {
    let strip: Strip
    let status: RowStatus
    let meter: [MeterSegment]?
    var id: String { strip.id }
}

struct RepoGroup: Equatable, Identifiable {
    let repo: String
    let error: String?
    let rows: [RowModel]
    var id: String { repo }
}

enum Presentation {
    /// Stage words in the status idiom, capitalised, and as the profile's stage labels.
    static let phaseWords = ["Gather", "Review", "Check", "Land"]

    static func strips(from run: RunState?) -> [Strip] {
        guard let run else { return [] }
        return run.repos.flatMap { repo in
            repo.prs.map { pr in
                Strip(repo: repo.slug, number: pr.n, author: pr.author, title: pr.title, reason: PRFilter.displayReason(pr.reason),
                      stage: pr.stage.rank + 1, active: pr.active, verdict: pr.verdict, tokens: pr.tokens,
                      carriedFrom: pr.carriedFrom, draft: pr.draft ?? false, flagged: pr.flagged ?? false,
                      skipReason: pr.skipReason, changedLines: pr.changedLines, isDraftPR: pr.isDraftPR ?? false)
            }
        }
    }

    static func headerKind(_ snap: Snapshot, now: Date) -> HeaderKind {
        if !snap.jobInstalled { return .notScheduled }
        let strips = Presentation.strips(from: snap.run)
        let changes = strips.filter { $0.verdict == .changes }.count
        if snap.running, let run = snap.run {
            if strips.isEmpty { return .preparing(phase: run.phase, started: run.started) }
            return .running(changes: changes, reviewing: strips.filter { $0.active && $0.verdict == nil }.count,
                            total: strips.count, landed: strips.filter { $0.verdict != nil }.count,
                            started: run.started)
        }
        if snap.dryRunning { return .dryRun }
        if snap.paused {
            return .paused(since: snap.pausedSince, lastStarted: snap.run?.started)
        }
        if let run = snap.run, run.finished != nil {
            if let message = failureMessage(run) {
                return .failed(reason: plainFailure(message), started: run.started, next: snap.nextRun)
            }
            if strips.isEmpty {
                return .emptyRun(repos: run.repos.count, next: snap.nextRun, lastStarted: run.started)
            }
            return .idle(changes: changes, next: snap.nextRun, lastStarted: run.started, total: strips.count)
        }
        if snap.run == nil {
            // Configured means config.toml has repos. Onboarding's dry run never becomes the current run, so a
            // configured user has no run until the first scheduled sweep.
            if snap.repoCount == 0 { return .notConfigured(next: snap.nextRun) }
            return .noSweeps(next: snap.nextRun, repos: snap.repoCount)
        }
        return .idle(changes: changes, next: snap.nextRun, lastStarted: snap.run?.started, total: strips.count)
    }

    /// The line under "Getting ready": the runner's phase in words, or listing when the phase is not known.
    static func preparingLine(_ phase: String?) -> String {
        if let phase, phase.hasPrefix("indexing ") {
            return "Refreshing the code graph for \(phase.dropFirst("indexing ".count))"
        }
        if let phase, phase.hasPrefix("listing PRs in ") {
            return "Listing open PRs in \(phase.dropFirst("listing PRs in ".count))"
        }
        return "Listing open PRs"
    }

    /// What to tell the user when a sweep ends. Dry runs never become current, so they never reach here. A finished
    /// sweep with nothing reviewed says nothing, unless it failed.
    /// The notice for a finished dry run: what it would have posted. Nothing was posted.
    static func dryRunNotice(_ run: RunState) -> SweepNotice {
        let strips = Presentation.strips(from: run)
        let changes = strips.filter { $0.verdict == .changes }.count
        let approvals = strips.filter { $0.verdict == .approve }.count
        return SweepNotice(title: "Dry run done",
                           body: "\(changes) would request changes, \(approvals) would approve. Nothing was posted.")
    }

    static func notice(_ run: RunState) -> SweepNotice? {
        guard run.finished != nil else { return nil }
        if run.kind == "review" {
            // A one-PR review by hand is not a sweep: it notifies only when it fails.
            return failureMessage(run).map { SweepNotice(title: "Review failed", body: $0) }
        }
        if let message = failureMessage(run) {
            return SweepNotice(title: "Sweep failed", body: message)
        }
        let prs = run.repos.flatMap(\.prs)
        let drafts = prs.filter { $0.draft == true }.count
        let changes = prs.filter { $0.verdict == .changes }.count
        let approved = prs.filter { $0.verdict == .approve }.count
        let reviewed = changes + approved
        guard reviewed > 0 else { return nil }
        if drafts > 0 {
            return SweepNotice(title: "Sweep done", body: "\(drafts) draft\(drafts == 1 ? "" : "s") to post")
        }
        if changes == 0 {
            return SweepNotice(title: "Sweep done", body: "All clear · \(reviewed) reviewed")
        }
        var body = "\(changes) need changes"
        if approved > 0 { body += " · \(approved) approved" }
        return SweepNotice(title: "Sweep done", body: body)
    }

    /// "Too large · 12,480 lines": line 3 of a PR skipped for size.
    static func sizeText(_ lines: Int) -> String {
        "Too large · \(lines.formatted()) lines"
    }

    /// Rough tokens for a PR of `changedLines`, from the last finished run: its tokens per reviewed PR, scaled by the
    /// PR's size against that run's average. nil when that run does not have the sizes to compare.
    static func reviewEstimate(_ run: RunState, changedLines: Int) -> Int? {
        guard run.finished != nil, run.tokens > 0 else { return nil }
        let reviewed = run.repos.flatMap(\.prs).filter { $0.verdict == .approve || $0.verdict == .changes }
        let sizes = reviewed.compactMap(\.changedLines)
        guard !reviewed.isEmpty, sizes.count == reviewed.count, sizes.reduce(0, +) > 0 else { return nil }
        let perPR = Double(run.tokens) / Double(reviewed.count)
        let average = Double(sizes.reduce(0, +)) / Double(sizes.count)
        return Int(perPR * Double(changedLines) / average)
    }

    /// The Review confirm text. The token sentence appears only when the last finished run allows an estimate.
    static func reviewWarning(changedLines: Int, limit: Int, last: RunState?) -> String {
        var text = "It changes \(changedLines.formatted()) lines, over your \(limit.formatted()) limit. "
            + "It will be split across several reviewers and may use a lot of tokens"
        if let last, last.finished != nil, last.tokens > 0 {
            let reviewed = last.repos.flatMap(\.prs).filter { $0.verdict == .approve || $0.verdict == .changes }.count
            if reviewed > 0 {
                text += " (the last run used \(compactTokens(last.tokens)) for \(reviewed) PR\(reviewed == 1 ? "" : "s"))"
            }
            text += "."
            if let estimate = reviewEstimate(last, changedLines: changedLines) {
                text += " This PR is about \(compactTokens(estimate)) tokens, going by the last run."
            }
            return text
        }
        return text + "."
    }

    /// The first line of the run's error, or of the first repo error. nil when the run had none.
    static func failureMessage(_ run: RunState) -> String? {
        let message = run.error ?? run.repos.compactMap(\.error).first
        return message?.split(separator: "\n").first.map(String.init)
    }

    /// The run error in plain words for the header. "claude exited 1: ..." becomes a sentence about the agent.
    static func plainFailure(_ message: String) -> String {
        if let range = message.range(of: #"claude exited (\d+)"#, options: .regularExpression) {
            let code = message[range].replacingOccurrences(of: "claude exited ", with: "")
            return "The review agent stopped early (exit \(code))"
        }
        return message
    }

    /// Sort order (docs/design.md, pass 4): needs changes, no result, in flight (queued last), approved, skipped.
    static func rank(_ s: Strip, running: Bool) -> Int {
        if s.verdict == .changes { return 0 }
        if s.verdict == nil && !s.active && !running { return 1 }
        if s.active || (running && s.verdict == nil) { return 2 }
        if s.verdict == .approve { return 3 }
        return 4
    }

    /// In-flight rows lead with the latest stage. Otherwise ties go by PR number, highest first.
    static func before(_ a: Strip, _ b: Strip, running: Bool) -> Bool {
        let ra = rank(a, running: running), rb = rank(b, running: running)
        if ra != rb { return ra < rb }
        if ra == 2 {
            let sa = a.active ? a.stage : 0, sb = b.active ? b.stage : 0
            if sa != sb { return sa > sb }
        }
        return a.number > b.number
    }

    static func rows(from strips: [Strip], running: Bool, repos: [RepoState]) -> [RepoGroup] {
        let order = repos.map(\.slug)
        let uniqueOrder = order.isEmpty ? Array(Set(strips.map(\.repo))).sorted() : order
        return uniqueOrder.map { slug in
            let mine = strips.filter { $0.repo == slug }.sorted { before($0, $1, running: running) }
            return RepoGroup(repo: slug, error: repos.first { $0.slug == slug }?.error,
                             rows: mine.map { row($0, running: running) })
        }
    }

    static func row(_ s: Strip, running: Bool) -> RowModel {
        RowModel(strip: s, status: status(s, running: running), meter: meter(s))
    }

    static func status(_ s: Strip, running: Bool) -> RowStatus {
        switch s.verdict {
        case .changes?: return .changes
        case .approve?: return .approved
        case .skipped?: return .skipped(reason: s.reason)
        case nil:
            if s.active { return .active(phase: phaseWords[min(max(s.stage, 1), 4) - 1]) }
            return running ? .queued : .noResult
        }
    }

    /// The four dashes: done segments before the current stage, the current one in the system blue. Only
    /// active rows have a meter.
    static func meter(_ s: Strip) -> [MeterSegment]? {
        guard s.active, s.verdict == nil else { return nil }
        let current = min(max(s.stage, 1), 4) - 1
        return (0..<4).map { $0 < current ? .done : ($0 == current ? .current : .future) }
    }
}

/// "1.2k", "84k", "3.1M". Token counts in the menu.
func compactTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
    default: return "\(n)"
    }
}
