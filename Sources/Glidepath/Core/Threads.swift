import Foundation

/// Something on a PR that asks for an answer: a review thread, a change-request review, or a plain comment.
struct Ask: Codable, Equatable {
    var id: String
    /// thread, review or comment.
    var kind: String
    var author: String
    var isBot: Bool
    var body: String
    var path: String?
    var line: Int?
    var databaseId: Int?
}

enum Threads {
    static let bots = ["coderabbitai", "copilot-pull-request-reviewer", "github-actions"]
    static let praise: Set<String> = ["lgtm", "looks", "good", "approved", "+1", "👍", "🚀"]

    static func isBot(_ login: String) -> Bool {
        let lower = login.lowercased()
        return lower.hasSuffix("[bot]") || bots.contains(lower)
    }

    /// A comment that only says the change is fine: at most three words, all praise.
    static func isNoise(_ body: String) -> Bool {
        let words = body.lowercased().replacingOccurrences(of: "[.!,]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return !words.isEmpty && words.count <= 3 && words.allSatisfy(praise.contains)
    }

    /// What still asks for an answer from someone other than `me`. A thread is open when it is unresolved and its
    /// last comment is not `me`'s. A review counts when it requests changes with a body. A plain comment counts unless
    /// it is noise. Reviews and comments drop out once their id is in `answered`.
    static func actionable(_ pr: OpenPR, me: String, answered: Set<String>) -> [Ask] {
        func mine(_ login: String) -> Bool { login.caseInsensitiveCompare(me) == .orderedSame }
        var asks: [Ask] = []
        for thread in pr.threads where !thread.isResolved {
            guard let last = thread.comments.last, !mine(last.author) else { continue }
            let first = thread.comments[0]
            asks.append(Ask(id: thread.id, kind: "thread", author: last.author, isBot: isBot(last.author),
                            body: last.body, path: first.path, line: first.line, databaseId: last.databaseId))
        }
        for review in pr.reviews where review.state == "CHANGES_REQUESTED" && !review.body.isEmpty
            && !mine(review.author) && !answered.contains(review.id) {
            asks.append(Ask(id: review.id, kind: "review", author: review.author, isBot: isBot(review.author),
                            body: review.body, path: nil, line: nil, databaseId: review.databaseId))
        }
        for comment in pr.comments where !mine(comment.author) && !answered.contains(comment.id)
            && !isNoise(comment.body) {
            asks.append(Ask(id: comment.id, kind: "comment", author: comment.author, isBot: isBot(comment.author),
                            body: comment.body, path: nil, line: nil, databaseId: comment.databaseId))
        }
        return asks
    }
}

/// Checks a reply before it is posted as the user. Nil when it may go; otherwise the reason it may not.
enum ReplyGuard {
    static let maxLength = 600

    static func check(_ text: String, author: String, slug: String, n: Int) -> String? {
        if text.count > maxLength { return "Reply is over \(maxLength) characters." }
        for match in matches(#"(?<![A-Za-z0-9])@[A-Za-z0-9-]+"#, in: text) {
            let login = String(match.dropFirst())
            if login.caseInsensitiveCompare(author) != .orderedSame { return "Reply mentions @\(login)." }
        }
        let commit = "https://github.com/" + NSRegularExpression.escapedPattern(for: slug)
            + "/(pull/\(n)/)?commits?/[0-9a-f]{7,40}"
        for link in matches(#"https?://\S+"#, in: text) {
            if link.range(of: "\\A\(commit)\\z", options: .regularExpression) == nil {
                return "Reply has a link that is not a commit of this PR."
            }
        }
        return nil
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
