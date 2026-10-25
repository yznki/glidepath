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
    var inFlight: [Row]
    var reviewed: [Row]
    var stopped: [Row]
    var skipped: [SkipKind: [Row]]
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
        ownRows = run.repos.flatMap { repo in
            repo.prs.filter { $0.carriedFrom == nil }.map { Row(slug: repo.slug, pr: $0) }
        }
        inFlight = ownRows.filter { $0.pr.active }
        reviewed = ownRows.filter { $0.pr.verdict == .approve || $0.pr.verdict == .changes }
        stopped = running ? [] : ownRows.filter { !$0.pr.active && $0.pr.verdict == nil }

        var groups: [SkipKind: [Row]] = [:]
        for row in ownRows where row.pr.verdict == .skipped {
            groups[RunDigest.skipKind(row.pr), default: []].append(row)
        }
        skipped = groups
        let skipCount = groups.values.reduce(0) { $0 + $1.count }

        if running {
            let toReviewCount = ownRows.filter { $0.pr.verdict != .skipped }.count
            lead = "\(reviewed.count) of \(toReviewCount) reviewed"
        } else if !stopped.isEmpty {
            lead = "Reviewed \(reviewed.count), \(stopped.count) stopped."
        } else if reviewed.isEmpty {
            lead = "Nothing reviewed."
        } else {
            lead = "Reviewed \(reviewed.count) of \(ownRows.count)."
        }

        if skipCount == 0 {
            rest = ""
        } else if groups.keys.allSatisfy({ $0 == .alreadyReviewed }) {
            rest = "You'd already reviewed the other \(skipCount), and nothing changed since."
        } else {
            let parts = SkipKind.allCases.compactMap { kind -> String? in
                guard let n = groups[kind]?.count else { return nil }
                return RunDigest.groupText(kind, n)
            }
            rest = "\(skipCount) skipped: " + parts.joined(separator: ", ") + "."
        }
    }

    /// "Sweep" for a sweep, "<login>'s PRs" for an author, "owner/name #n" for one PR, "<k> PRs" for several.
    static func title(for run: RunState) -> String {
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
}
