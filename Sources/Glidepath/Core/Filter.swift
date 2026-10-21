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

    /// Rules from SPEC "Run flow" step 2. Cheap checks run first; the collaborator and reviews
    /// lookups are API calls and only happen for PRs that get that far. A lookup that fails skips
    /// the PR with a reason instead of failing the repo.
    static func evaluate(_ pr: PRInfo, me: String, includeOwn: Bool = false, authors: AuthorPolicy, limits: Limits,
                         isCollaborator: () -> Bool?, reviewedHeads: () -> Set<String>?) -> Decision {
        if !includeOwn && pr.author.caseInsensitiveCompare(me) == .orderedSame { return .skip("your own PR") }
        if pr.isDraft { return .skip("draft") }
        // A bot listed by name in `authors` is an explicit opt-in.
        let listed: Bool
        if case .logins(let logins) = authors {
            listed = logins.contains { $0.caseInsensitiveCompare(pr.author) == .orderedSame }
        } else {
            listed = false
        }
        if !listed && (pr.authorIsBot || pr.author.hasSuffix("[bot]")) { return .skip("bot author") }
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
        guard let heads = reviewedHeads() else { return .skip("could not read existing reviews") }
        if heads.contains(pr.headSha) { return .skip("already reviewed at this head") }
        return .keep
    }
}
