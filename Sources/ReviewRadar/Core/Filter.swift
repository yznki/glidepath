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
    /// Rules from SPEC "Run flow" step 2, checked in a fixed order so the skip reason is stable.
    /// `isCollaborator` is only called when the policy needs it.
    static func evaluate(_ pr: PRInfo, me: String, authors: AuthorPolicy, limits: Limits,
                         reviewedHeads: Set<String>, isCollaborator: () -> Bool) -> Decision {
        if pr.author.caseInsensitiveCompare(me) == .orderedSame { return .skip("your own PR") }
        if pr.isDraft { return .skip("draft") }
        if pr.authorIsBot || pr.author.hasSuffix("[bot]") { return .skip("bot author") }
        switch authors {
        case .collaborators:
            if !isCollaborator() { return .skip("author is not a collaborator") }
        case .anyone:
            break
        case .logins(let logins):
            if !logins.contains(where: { $0.caseInsensitiveCompare(pr.author) == .orderedSame }) {
                return .skip("author not in authors list")
            }
        }
        if reviewedHeads.contains(pr.headSha) { return .skip("already reviewed at this head") }
        if pr.changedLines > limits.maxChangedLines {
            return .skip("too large (\(pr.changedLines) changed lines)")
        }
        return .keep
    }
}
