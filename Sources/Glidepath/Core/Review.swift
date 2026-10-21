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
    /// `head` comes from run state, never from the draft. `note` is the flag note, appended to the body.
    /// `own` is true when the PR is the user's own: GitHub accepts only COMMENT there, whatever `posting` says.
    /// Draft mode picks the same event as review mode; the user decides when it is posted.
    static func validate(_ d: Draft, files: Set<String>, posting: Posting, head: String, own: Bool = false,
                         note: String? = nil) throws -> ReviewPayload {
        guard ["approve", "changes"].contains(d.verdict) else {
            throw CommandError("verdict must be approve or changes")
        }
        let reason = d.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= maxReason, !reason.contains("\n") else {
            throw CommandError("reason must be one line, 1 to \(maxReason) characters")
        }
        var body = d.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw CommandError("body is empty") }
        if let note { body += "\n\n" + note }
        try checkContent(body)
        guard body.count <= maxBody else { throw CommandError("body is \(body.count) characters; limit is \(maxBody)") }
        guard d.comments.count <= maxComments else {
            throw CommandError("\(d.comments.count) comments; the limit is \(maxComments)")
        }
        var comments: [PayloadComment] = []
        for c in d.comments {
            comments.append(try checkComment(c.path, c.line, c.side, c.body, files: files))
        }

        let payload: ReviewPayload
        switch own ? Posting.comment : posting {
        case .comment:
            // COMMENT reviews carry the verdict in the first line of the body.
            let verdictLine = d.verdict == "approve" ? "Verdict: approve" : "Verdict: changes"
            payload = ReviewPayload(commit_id: head, event: "COMMENT",
                                    body: verdictLine + "\n\n" + body, comments: comments)
        case .review, .draft:
            let event = d.verdict == "approve" ? "APPROVE" : "REQUEST_CHANGES"
            payload = ReviewPayload(commit_id: head, event: event, body: body, comments: comments)
        }
        try checkPayload(payload, files: files, own: own)
        return payload
    }

    /// Room for the verdict line that a COMMENT payload adds in front of the body.
    static let verdictLineRoom = 20

    /// The checks a payload must pass before it is sent. `validate` runs them on what it built; `drafts post` runs
    /// them again on the draft file, which is data on disk and is never trusted.
    static func checkPayload(_ p: ReviewPayload, files: Set<String>, own: Bool) throws {
        guard ["APPROVE", "REQUEST_CHANGES", "COMMENT"].contains(p.event) else {
            throw CommandError("event must be APPROVE, REQUEST_CHANGES or COMMENT")
        }
        if own, p.event != "COMMENT" { throw CommandError("your own PR takes only COMMENT reviews") }
        guard !p.body.isEmpty, p.body.count <= maxBody + verdictLineRoom else {
            throw CommandError("body is \(p.body.count) characters; limit is \(maxBody)")
        }
        try checkContent(p.body)
        guard p.comments.count <= maxComments else {
            throw CommandError("\(p.comments.count) comments; the limit is \(maxComments)")
        }
        for c in p.comments {
            _ = try checkComment(c.path, c.line, c.side, c.body, files: files)
        }
    }

    /// One inline comment: a file in the PR, a line from 1, side RIGHT only, and a bounded body of plain text.
    static func checkComment(_ path: String, _ line: Int, _ side: String?, _ body: String, files: Set<String>) throws -> PayloadComment {
        guard files.contains(path) else { throw CommandError("comment path \(path) is not a file in this PR") }
        guard line >= 1 else { throw CommandError("comment on \(path) has line \(line)") }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CommandError("comment on \(path):\(line) is empty") }
        guard text.count <= maxCommentBody else {
            throw CommandError("comment on \(path):\(line) is \(text.count) characters; limit is \(maxCommentBody)")
        }
        try checkContent(text)
        if let side, side != "RIGHT" { throw CommandError("only side RIGHT is allowed") }
        return PayloadComment(path: path, line: line, side: "RIGHT", body: text)
    }
}

/// `flag_paths`: prefix matches on a PR's changed files, computed by the wrappers from GitHub's file list.
enum FlagPaths {
    /// Changed files that start with one of the prefixes, in the order GitHub lists them.
    static func matches(_ files: [String], prefixes: [String]) -> [String] {
        files.filter { file in prefixes.contains { file.hasPrefix($0) } }
    }

    /// The line appended to a review body: the note and up to three matched paths. nil when nothing matched.
    static func note(_ text: String, matches: [String]) -> String? {
        guard !matches.isEmpty else { return nil }
        let shown = matches.prefix(3).joined(separator: ", ")
        let more = matches.count > 3 ? ", +\(matches.count - 3) more" : ""
        return "**Note:** \(text) (\(shown)\(more))"
    }
}
