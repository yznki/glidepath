import Foundation

struct PRInfo: Equatable {
    var n: Int
    var title: String
    var author: String
    var authorIsBot: Bool
    var isDraft: Bool
    var headSha: String
    var additions: Int
    var deletions: Int

    var changedLines: Int { additions + deletions }
}

enum Decision: Equatable {
    case keep
    case skip(String)
}

enum PRFilter {
    /// The reason a PR over `max_changed_lines` is skipped. The runner keys the Review action on this prefix.
    static let tooLargeReason = "too large"

    /// The reason the user's own PR is skipped. `glidepath review` keys its include_own hint on it.
    static let ownPRReason = "your own PR"

    /// The reason a PR past `max_prs_per_run` waits for the next sweep.
    static func heldForNextSweep(cap: Int) -> String { "next sweep · \(cap) per sweep" }

    /// The reason as users read it. Runs stored before the wording change hold the config key, which shows as "next sweep".
    static func displayReason(_ stored: String?) -> String? {
        stored == "over max_prs_per_run" ? "next sweep" : stored
    }

    /// Rules from SPEC "Run flow" step 2. Cheap checks run first; the collaborator and reviews
    /// lookups are API calls and only happen for PRs that get that far. A lookup that fails skips
    /// the PR with a reason instead of failing the repo.
    /// `draftHeads` are the heads of this PR's open drafts: a draft at the current head counts as reviewed.
    /// `reviewDrafts` and `includeBots` turn off the draft and bot skips. The runner passes the repo's value of
    /// `review_drafts` when it has one, else the global value.
    static func evaluate(_ pr: PRInfo, me: String, includeOwn: Bool = false, reviewDrafts: Bool = false,
                         includeBots: Bool = false, authors: AuthorPolicy, limits: Limits,
                         draftHeads: Set<String> = [], isCollaborator: () -> Bool?, reviewedHeads: () -> Set<String>?) -> Decision {
        if !includeOwn && pr.author.caseInsensitiveCompare(me) == .orderedSame { return .skip(ownPRReason) }
        if pr.isDraft && !reviewDrafts { return .skip("draft") }
        // A bot listed by name in `authors` is an explicit opt-in.
        let listed: Bool
        if case .logins(let logins) = authors {
            listed = logins.contains { $0.caseInsensitiveCompare(pr.author) == .orderedSame }
        } else {
            listed = false
        }
        if !includeBots && !listed && (pr.authorIsBot || pr.author.hasSuffix("[bot]")) { return .skip("bot author") }
        if pr.changedLines > limits.maxChangedLines {
            return .skip("\(tooLargeReason) (\(pr.changedLines) changed lines)")
        }
        switch authors {
        case .collaborators:
            switch isCollaborator() {
            case true?: break
            case false?: return .skip("author is not a collaborator")
            case nil: return .skip("cannot read collaborator permission (needs push access); list authors explicitly")
            }
        case .anyone:
            break
        case .logins:
            if !listed { return .skip("author not in authors list") }
        }
        if draftHeads.contains(pr.headSha) { return .skip("draft waiting") }
        guard let heads = reviewedHeads() else { return .skip("could not read existing reviews") }
        if heads.contains(pr.headSha) { return .skip("already reviewed at this head") }
        return .keep
    }
}
