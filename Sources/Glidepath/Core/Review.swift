import Foundation

struct CommandError: Error, CustomStringConvertible, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `<scratch>/<n>/final.json`, written by the checker. The wrapper decides everything that goes to
/// GitHub except the text, the verdict and the comment placement.
struct Draft: Codable, Equatable {
    var verdict: String
    var reason: String
    var body: String
    var comments: [DraftComment]
}

struct DraftComment: Codable, Equatable {
    var path: String
    var line: Int
    var side: String?
    var body: String
}

/// The exact JSON the reviews API receives.
struct ReviewPayload: Codable, Equatable {
    var commit_id: String
    var event: String
    var body: String
    var comments: [PayloadComment]
}

struct PayloadComment: Codable, Equatable {
    var path: String
    var line: Int
    var side: String
    var body: String
}

enum ReviewValidator {
    static let maxBody = 6000
    static let maxCommentBody = 1500
    static let maxComments = 5
    static let maxReason = 60

    /// Reviews are text. Images, iframes and links to other hosts can carry tracking pixels or
    /// lure readers, so they are refused before anything is posted.
    static func checkContent(_ text: String) throws {
        let lower = text.lowercased()
        if lower.contains("![") {
            throw CommandError("remove the image (![); reviews are plain text")
        }
        if text.range(of: #"<[A-Za-z/]"#, options: .regularExpression) != nil {
            throw CommandError("remove the HTML (a < followed by a letter or /); reviews are plain text")
        }
        if lower.contains("www.") {
            throw CommandError("remove the www. link; write full github.com links only")
        }
        if let scheme = text.range(of: #"(?i)(?<![A-Za-z])(ftp|mailto|javascript|data):"#, options: .regularExpression) {
            throw CommandError("remove the \(text[scheme].dropLast()): link; only github.com links are allowed")
        }
        for host in urlHosts(in: text) where host != "github.com" {
            throw CommandError("remove the link to \(host); only github.com links are allowed")
        }
    }

    /// Lowercased hosts of every http or https URL in the text.
    static func urlHosts(in text: String) -> [String] {
        let terminators: Set<Character> = [" ", "\n", "\r", "\t", ")", "]", ">", "<", "\"", "'", "`"]
        var hosts: [String] = []
        for scheme in ["https://", "http://"] {
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: scheme, options: .caseInsensitive, range: search) {
                var end = found.upperBound
                while end < text.endIndex, !terminators.contains(text[end]) { end = text.index(after: end) }
                let rest = text[found.upperBound..<end]
                let host = rest.prefix { !"/?#:".contains($0) }
                hosts.append(host.lowercased())
                search = found.upperBound..<text.endIndex
            }
        }
        return hosts
    }

    /// Checks a draft against the PR's file list and the repo's posting mode, and builds the payload.
    /// `head` comes from run state, never from the draft.
    /// `own` is true when the PR is the user's own: GitHub accepts only COMMENT there, whatever `posting` says.
    static func validate(_ d: Draft, files: Set<String>, posting: Posting, head: String, own: Bool = false) throws -> ReviewPayload {
        guard ["approve", "changes"].contains(d.verdict) else {
            throw CommandError("verdict must be approve or changes")
        }
        let reason = d.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= maxReason, !reason.contains("\n") else {
            throw CommandError("reason must be one line, 1 to \(maxReason) characters")
        }
        let body = d.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw CommandError("body is empty") }
        try checkContent(body)
        guard body.count <= maxBody else { throw CommandError("body is \(body.count) characters; limit is \(maxBody)") }
        guard d.comments.count <= maxComments else {
            throw CommandError("\(d.comments.count) comments; the limit is \(maxComments)")
        }
        var comments: [PayloadComment] = []
        for c in d.comments {
            guard files.contains(c.path) else { throw CommandError("comment path \(c.path) is not a file in this PR") }
            guard c.line >= 1 else { throw CommandError("comment on \(c.path) has line \(c.line)") }
            let text = c.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw CommandError("comment on \(c.path):\(c.line) is empty")
            }
            guard text.count <= maxCommentBody else {
                throw CommandError("comment on \(c.path):\(c.line) is \(text.count) characters; limit is \(maxCommentBody)")
            }
            try checkContent(text)
            if let side = c.side, side != "RIGHT" { throw CommandError("only side RIGHT is allowed") }
            comments.append(PayloadComment(path: c.path, line: c.line, side: "RIGHT", body: text))
        }

        switch own ? Posting.comment : posting {
        case .comment:
            // COMMENT reviews carry the verdict in the first line of the body.
            let verdictLine = d.verdict == "approve" ? "Verdict: approve" : "Verdict: changes"
            return ReviewPayload(commit_id: head, event: "COMMENT",
                                 body: verdictLine + "\n\n" + body, comments: comments)
        case .review:
            let event = d.verdict == "approve" ? "APPROVE" : "REQUEST_CHANGES"
            return ReviewPayload(commit_id: head, event: event, body: body, comments: comments)
        }
    }
}
