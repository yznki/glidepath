import Foundation

/// What one run did, in the words the Now and History sections and the popover show. Pure: built from a run file.
struct RunDigest: Equatable {
    /// Why a PR was skipped. The digest lists the groups in this order.
    enum SkipKind: CaseIterable, Equatable {
        case own, bot, alreadyReviewed, draft, tooLarge, other
    }

    struct Row: Equatable {
        var slug: String
        var pr: PRState

        /// The PR's key in the window: `owner/name#n`, as `Strip.id`.
        var stripID: String { "\(slug)#\(pr.n)" }
    }

    var title: String
    var running: Bool
    /// This run's own rows. Rows carried over from an earlier run belong to that run and are left out.
    var ownRows: [Row]
    /// Rows still in flight. Only a run that is going has any; a run that died leaves its rows as stopped.
    var inFlight: [Row]
    var reviewed: [Row]
    /// Rows with no verdict once the run is not going: the review was stopped or died before it reached one.
    var stopped: [Row]
    var skipped: [SkipKind: [Row]]
    /// The run's error, or its first repo error. nil when the run had none.
    var failed: String?
    /// The bold part of the sentence, such as "Reviewed 4 of 25.".
    var lead: String
    /// The muted part of the sentence, such as "You'd already reviewed the other 21, and nothing changed since.".
    var rest: String

    /// Own rows the run reviews: every own row that is not skipped.
    var toReview: Int { ownRows.filter { $0.pr.verdict != .skipped }.count }

    /// Rows among `toReview` that have a verdict.
    var done: Int { reviewed.count }

    init(run: RunState, running: Bool) {
        self.running = running
        title = RunDigest.title(for: run)
        let own = run.repos.flatMap { repo in
            repo.prs.filter { $0.carriedFrom == nil }.map { Row(slug: repo.slug, pr: $0) }
        }
        ownRows = own
        inFlight = running ? own.filter { $0.pr.active } : []
        reviewed = own.filter { $0.pr.verdict == .approve || $0.pr.verdict == .changes }
        // A tend round has no verdict by design, so it never counts as stopped.
        let unfinished = running || run.kind == "tend" ? [] : own.filter { $0.pr.verdict == nil }
        stopped = unfinished

        var groups: [SkipKind: [Row]] = [:]
        for row in own where row.pr.verdict == .skipped {
            groups[RunDigest.skipKind(row.pr), default: []].append(row)
        }
        skipped = groups
        let skipCount = groups.values.reduce(0) { $0 + $1.count }
        failed = Presentation.failureMessage(run)

        if let failed {
            lead = "Failed."
            rest = failed
        } else if run.kind == "tend" {
            // A tend round has one row, with no verdict: its summary is the sentence.
            lead = title
            rest = own.first?.pr.reason ?? ""
        } else {
            if running {
                let toReviewCount = own.filter { $0.pr.verdict != .skipped }.count
                lead = "\(reviewed.count) of \(toReviewCount) reviewed."
            } else if !unfinished.isEmpty && reviewed.isEmpty {
                lead = "\(unfinished.count) stopped."
            } else if !unfinished.isEmpty {
                lead = "Reviewed \(reviewed.count), \(unfinished.count) stopped."
            } else if reviewed.isEmpty {
                lead = "Nothing reviewed."
            } else {
                lead = "Reviewed \(reviewed.count) of \(own.count)."
            }
            rest = RunDigest.skipSentence(groups: groups, count: skipCount, reviewed: reviewed.count)
        }
    }

    /// "Sweep" for a sweep, "<login>'s PRs" for an author, "owner/name #n" for one PR, "<k> PRs" for several.
    static func title(for run: RunState) -> String {
        if run.kind == "tend" {
            // The target is "pr:owner/name#n"; the number is what follows the last "#".
            let number = "#" + (run.target?.split(separator: "#").last.map(String.init) ?? "?")
            switch run.tendAction {
            case "fixed": return "Fixed CI on \(number)"
            case "reran": return "Reran \(run.tendCheck ?? "CI") on \(number)"
            case "held": return "Fix held on \(number)"
            case "stuck": return "Stuck on \(number)"
            default: return "Tend on \(number)"
            }
        }
        guard run.kind != nil else { return "Sweep" }
        guard let target = run.target else { return "Review" }
        if target.hasPrefix("author:") { return "\(target.dropFirst("author:".count))'s PRs" }
        if target.hasPrefix("prs:") {
            let refs = target.dropFirst("prs:".count).split(separator: ",")
            if refs.count == 1 { return String(refs[0]).replacingOccurrences(of: "#", with: " #") }
            return "\(refs.count) PRs"
        }
        return "Review"
    }

    /// The group a skipped PR belongs to, from the reason the runner stored.
    static func skipKind(_ pr: PRState) -> SkipKind {
        let reason = pr.reason ?? ""
        if reason == PRFilter.ownPRReason { return .own }
        if reason == "bot author" { return .bot }
        if reason.hasPrefix("already reviewed") { return .alreadyReviewed }
        if reason == "draft" { return .draft }
        if pr.skipReason == "size" || reason.hasPrefix(PRFilter.tooLargeReason) { return .tooLarge }
        return .other
    }

    static func groupText(_ kind: SkipKind, _ n: Int) -> String {
        switch kind {
        case .own: return "\(n) yours"
        case .bot: return n == 1 ? "1 bot" : "\(n) bots"
        case .alreadyReviewed: return "\(n) already reviewed"
        case .draft: return n == 1 ? "1 draft" : "\(n) drafts"
        case .tooLarge: return "\(n) too large"
        case .other: return "\(n) other"
        }
    }

    /// The muted sentence about skips. When every skip was already reviewed, it says so; otherwise it groups them.
    private static func skipSentence(groups: [SkipKind: [Row]], count: Int, reviewed: Int) -> String {
        guard count > 0 else { return "" }
        if groups.keys.allSatisfy({ $0 == .alreadyReviewed }) {
            if reviewed == 0 {
                let what = count == 1 ? "the one PR" : "all \(count)"
                return "You'd already reviewed \(what), and nothing changed since."
            }
            let what = count == 1 ? "the other one" : "the other \(count)"
            return "You'd already reviewed \(what), and nothing changed since."
        }
        let parts = SkipKind.allCases.compactMap { kind -> String? in
            guard let n = groups[kind]?.count else { return nil }
            return groupText(kind, n)
        }
        return "\(count) skipped: " + parts.joined(separator: ", ") + "."
    }
}
