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
    /// For a thread: every comment in it, oldest first, for the evidence file.
    var thread: [ThreadComment] = []

    /// What `TendPR.handled` records for this ask: a thread's last comment id, and "" for a review or comment.
    var handledMark: String { kind == "thread" ? (thread.last?.id ?? "") : "" }

    /// The login whose change request a reply to this ask answers: a review's author, a thread's first commenter.
    var reviewer: String? {
        switch kind {
        case "review": return author
        case "thread": return thread.first?.author
        default: return nil
        }
    }
}

enum Threads {
    static let bots = ["coderabbitai", "copilot-pull-request-reviewer", "github-actions"]
    static let praise: Set<String> = ["lgtm", "looks", "good", "approved", "+1", "👍", "🚀"]

    /// A bot by login, or a review or comment that carries the Glidepath marker: a teammate's Glidepath is a bot too.
    static func isBot(_ login: String, body: String = "") -> Bool {
        let lower = login.lowercased()
        return lower.hasSuffix("[bot]") || bots.contains(lower) || body.contains(ReviewValidator.marker)
    }

    /// A comment that only says the change is fine: at most three words, all praise.
    static func isNoise(_ body: String) -> Bool {
        let words = body.lowercased().replacingOccurrences(of: "[.!,]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return !words.isEmpty && words.count <= 3 && words.allSatisfy(praise.contains)
    }

    /// What still asks for an answer from someone other than `me`. A thread is open when it is unresolved, its last
    /// comment is not `me`'s, that comment is not noise, and `handled` does not name it. A review counts when it is its
    /// author's latest review, requests changes with a body, and is not answered. A plain comment counts unless it is
    /// noise, from a bot, answered or handled, so bot summaries never start a round. A newer comment makes a handled
    /// thread actionable again.
    static func actionable(_ pr: OpenPR, me: String, answered: Set<String>, handled: [String: String] = [:]) -> [Ask] {
        func mine(_ login: String) -> Bool { login.caseInsensitiveCompare(me) == .orderedSame }
        var asks: [Ask] = []
        for thread in pr.threads where !thread.isResolved {
            guard let last = thread.comments.last, !mine(last.author), !isNoise(last.body),
                  handled[thread.id] != last.id else { continue }
            let first = thread.comments[0]
            asks.append(Ask(id: thread.id, kind: "thread", author: last.author, isBot: isBot(last.author, body: last.body),
                            body: last.body, path: first.path, line: first.line, databaseId: last.databaseId,
                            thread: thread.comments))
        }
        // Reviews are in time order, so the last one an author left is their latest.
        var latest: [String: String] = [:]
        for review in pr.reviews { latest[review.author] = review.id }
        for review in pr.reviews where review.state == "CHANGES_REQUESTED" && !review.body.isEmpty
            && !mine(review.author) && !answered.contains(review.id) && handled[review.id] == nil
            && latest[review.author] == review.id {
            asks.append(Ask(id: review.id, kind: "review", author: review.author, isBot: isBot(review.author, body: review.body),
                            body: review.body, path: nil, line: nil, databaseId: review.databaseId))
        }
        for comment in pr.comments where !mine(comment.author) && !answered.contains(comment.id)
            && handled[comment.id] == nil && !isNoise(comment.body) && !isBot(comment.author, body: comment.body) {
            asks.append(Ask(id: comment.id, kind: "comment", author: comment.author, isBot: false,
                            body: comment.body, path: nil, line: nil, databaseId: comment.databaseId))
        }
        return asks
    }

    /// The asks a self-review with changes raised, minus those already answered. Empty once the review is done.
    static func selfAsks(_ review: SelfReview, answered: Set<String>) -> [Ask] {
        guard review.verdict == "changes", !review.done else { return [] }
        let head7 = String(review.head.prefix(7))
        return review.findings.enumerated().compactMap { i, f in
            let id = "self-\(head7)-\(i)"
            guard !answered.contains(id) else { return nil }
            // A finding with no file (a review with changes and no inline comment) has no path or line.
            let placed = !f.path.isEmpty
            return Ask(id: id, kind: "self", author: "self-review", isBot: false, body: f.body,
                       path: placed ? f.path : nil, line: placed ? f.line : nil)
        }
    }
}

/// Checks a reply before it is posted as the user. Nil when it may go; otherwise the reason it may not.
enum ReplyGuard {
    static let maxLength = 600

    static func check(_ text: String, author: String, slug: String, n: Int) -> String? {
        if text.count > maxLength { return "Reply is over \(maxLength) characters." }
        // GitHub logins have no `[bot]` suffix in the mention, so the author's login is compared without it.
        let login = author.lowercased().hasSuffix("[bot]") ? String(author.dropLast(5)) : author
        for match in matches(#"(?<![A-Za-z0-9])@[A-Za-z0-9-]+"#, in: text) {
            let mentioned = String(match.dropFirst())
            if mentioned.caseInsensitiveCompare(login) != .orderedSame { return "Reply mentions @\(mentioned)." }
        }
        // A commit link of this PR is allowed. Once those are gone, nothing that could be a link or markup may remain.
        let commit = "https://github.com/" + NSRegularExpression.escapedPattern(for: slug)
            + "/(pull/\(n)/)?commits?/[0-9a-f]{7,40}(?=[\\s.,;:!?)]|$)"
        let rest = text.replacingOccurrences(of: commit, with: "", options: [.regularExpression, .caseInsensitive])
        let lower = rest.lowercased()
        let markers = ["://", "www.", "](", "![", "<a", "<img"]
        if markers.contains(where: { lower.contains($0) })
            || rest.range(of: #"//[a-z0-9-]+\.[a-z]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "Reply has a link or markup that is not a commit of this PR."
        }
        return nil
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
