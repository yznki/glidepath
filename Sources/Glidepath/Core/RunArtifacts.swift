import Foundation

/// What one PR's run left in its scratch folder, for the flight recorder. Scratch is pruned after seven days, so every
/// field is empty when its file is missing.
struct RunArtifacts: Equatable {
    /// One review: a draft, or the checker's final. Comments are placed by path and line.
    struct Review: Equatable {
        var verdict: Verdict?
        var reason: String?
        var body: String
        var comments: [Comment]
    }

    struct Comment: Equatable {
        var path: String
        var line: Int
        var body: String
    }

    /// The PR's folder, when it exists. Nil for a PR that left no scratch (a filter skip, or pruned).
    var folder: String?
    /// The files listed in pr.json. GitHub lists at most 100, so the view shows "100+" at exactly 100.
    var fileCount: Int?
    var additions: Int?
    var deletions: Int?
    var headSha: String?
    var baseRef: String?
    /// The counts of threads.json's arrays.
    var reviewCount: Int?
    var reviewCommentCount: Int?
    var issueCommentCount: Int?
    /// Every draft*.json, in name order.
    var drafts: [Review] = []
    var final: Review?
    var blast: String?
    /// The owner's notes: notes.md, or the run's log when that is missing and the run reviewed this one PR.
    var notes: [String] = []
    /// The diff parts: every *.patch file except diff.patch.
    var diffParts = 0

    /// Every draft merged: changes when any draft says changes, and one comment per path and line.
    var draft: Review? { Self.merge(drafts) }

    /// The threads' comment count, or nil when threads.json was not read.
    var commentCount: Int? {
        let counts = [reviewCount, reviewCommentCount, issueCommentCount].compactMap { $0 }
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    /// `<scratch>/<runId>/<owner-name>/<n>`: the PR's folder, as the runner writes it.
    static func folder(_ paths: Paths, runId: String, slug: String, n: Int) -> String {
        paths.scratchDir + "/" + runId + "/" + slug.replacingOccurrences(of: "/", with: "-") + "/" + String(n)
    }

    /// Reads the PR folder. A folder that does not exist gives an empty value.
    static func load(folder: String) -> RunArtifacts {
        var out = RunArtifacts()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { return out }
        out.folder = folder

        if let pr = object(folder + "/pr.json") {
            out.fileCount = (pr["files"] as? [Any])?.count
            out.additions = pr["additions"] as? Int
            out.deletions = pr["deletions"] as? Int
            out.headSha = pr["headSha"] as? String
            out.baseRef = pr["baseRef"] as? String
        }
        if let threads = object(folder + "/threads.json") {
            out.reviewCount = (threads["reviews"] as? [Any])?.count
            out.reviewCommentCount = (threads["review_comments"] as? [Any])?.count
            out.issueCommentCount = (threads["issue_comments"] as? [Any])?.count
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        out.drafts = names.sorted().filter { $0.hasPrefix("draft") && $0.hasSuffix(".json") }
            .compactMap { review(folder + "/" + $0) }
        out.final = review(folder + "/final.json")
        out.blast = text(folder + "/blast.md")
        out.diffParts = names.filter { $0.hasSuffix(".patch") && $0 != "diff.patch" }.count
        if let notes = text(folder + "/notes.md") {
            out.notes = bullets(notes, limit: 5)
        } else {
            out.notes = logNotes(folder: folder)
        }
        return out
    }

    /// The bullets after "Notes for the owner" in the run's claude.log, but only when the run reviewed this one PR
    /// (the repo's folder has exactly one numbered PR folder).
    static func logNotes(folder: String) -> [String] {
        let repo = (folder as NSString).deletingLastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: repo)) ?? []
        guard siblings.filter({ Int($0) != nil }).count == 1, let log = text(repo + "/claude.log") else { return [] }
        var found: [String] = []
        var inNotes = false
        for line in log.components(separatedBy: "\n") {
            if line.contains("Notes for the owner") {
                inNotes = true
                continue
            }
            guard inNotes else { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") {
                found.append(String(t.dropFirst(2)))
            } else if !t.isEmpty, !found.isEmpty {
                break
            }
        }
        return Array(found.prefix(5))
    }

    /// The checker's changes to a PR's draft: which findings it kept, added and dropped, keyed by path and line.
    /// Empty when there is no final.
    static func merge(_ drafts: [Review]) -> Review? {
        guard !drafts.isEmpty else { return nil }
        let verdict: Verdict? = drafts.contains { $0.verdict == .changes } ? .changes
            : drafts.contains { $0.verdict == .approve } ? .approve : nil
        var seen = Set<String>()
        var comments: [Comment] = []
        for comment in drafts.flatMap(\.comments) where seen.insert(key(comment)).inserted {
            comments.append(comment)
        }
        return Review(verdict: verdict,
                      reason: drafts.lazy.compactMap(\.reason).first { !$0.isEmpty },
                      body: drafts.map(\.body).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                      comments: comments)
    }

    /// The blast radius text as the chip and the caller bullets. "GitNexus" when it ran, "grep only · partial" when
    /// grep stood in for it, "not run" when it is incomplete and lists no callers, else no chip.
    static func blastSummary(_ text: String) -> (chip: String, partial: Bool, bullets: [String]) {
        let lower = text.lowercased()
        let items = bullets(text, limit: 12)
        let gitnexus = lower.contains("gitnexus") && !lower.contains("not available")
        let grep = lower.contains("grep") || lower.contains("partial")
        let incomplete = lower.contains("not complete") || lower.contains("not available")
        if gitnexus { return ("GitNexus", false, items) }
        if grep { return ("grep only · partial", true, items) }
        if incomplete && items.isEmpty { return ("not run", true, items) }
        return ("", incomplete, items)
    }

    // MARK: Reading

    private static func key(_ comment: Comment) -> String { "\(comment.path):\(comment.line)" }

    private static func object(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func text(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// One draft or final. A file that is not JSON, or has no verdict, is ignored.
    private static func review(_ path: String) -> Review? {
        guard let json = object(path) else { return nil }
        let comments = (json["comments"] as? [[String: Any]] ?? []).compactMap { item -> Comment? in
            guard let path = item["path"] as? String, let line = item["line"] as? Int else { return nil }
            return Comment(path: path, line: line, body: item["body"] as? String ?? "")
        }
        return Review(verdict: (json["verdict"] as? String).flatMap(Verdict.init(rawValue:)),
                      reason: json["reason"] as? String,
                      body: json["body"] as? String ?? "",
                      comments: comments)
    }

    /// The lines that start with "- ", without the dash, up to `limit`.
    static func bullets(_ text: String, limit: Int) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { continue }
            out.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            if out.count == limit { break }
        }
        return out
    }
}

/// The checker's effect on a draft: findings kept, added and dropped, matched by path and line.
struct CheckerDelta {
    var kept: [RunArtifacts.Comment] = []
    var added: [RunArtifacts.Comment] = []
    var dropped: [RunArtifacts.Comment] = []
    var bodyChanged = false
    var verdictChanged: (from: Verdict, to: Verdict)?

    static func compute(drafts: [RunArtifacts.Review], final: RunArtifacts.Review?) -> CheckerDelta {
        guard let final, let draft = RunArtifacts.merge(drafts) else { return CheckerDelta() }
        let before = Set(draft.comments.map(FindingKey.init))
        let after = Set(final.comments.map(FindingKey.init))
        var delta = CheckerDelta()
        for comment in final.comments {
            if before.contains(FindingKey(comment)) { delta.kept.append(comment) } else { delta.added.append(comment) }
        }
        delta.dropped = draft.comments.filter { !after.contains(FindingKey($0)) }
        delta.bodyChanged = final.body.trimmingCharacters(in: .whitespacesAndNewlines)
            != draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let from = draft.verdict, let to = final.verdict, from != to {
            delta.verdictChanged = (from, to)
        }
        return delta
    }

    private struct FindingKey: Hashable {
        let path: String
        let line: Int
        init(_ comment: RunArtifacts.Comment) {
            path = comment.path
            line = comment.line
        }
    }
}
