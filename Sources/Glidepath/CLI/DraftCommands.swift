import Foundation

/// `glidepath drafts list|post|discard`. Drafts are posted by the user, never by a review session, so the bash
/// guard refuses this command inside one.
enum DraftCommands {
    static let usage = "usage: glidepath drafts list | post owner/name N | discard owner/name N"

    static func main(_ args: [String]) -> Int32 {
        do {
            let paths = Paths()
            switch args.first {
            case "list":
                let found = Drafts.all(paths)
                if found.isEmpty { print("no drafts") }
                for d in found {
                    let when = d.draft.created.formatted(.dateTime.month().day().hour().minute())
                    print("\(d.draft.slug) #\(d.draft.n) \(d.draft.event) \(when)")
                }
                return 0
            case "post", "discard":
                let (slug, n) = try target(Array(args.dropFirst()))
                if args.first == "post" {
                    print(try post(paths, slug, n))
                } else {
                    print(try discard(paths, slug, n))
                }
                return 0
            default:
                throw CommandError(usage)
            }
        } catch {
            eprint("\(error)")
            return 1
        }
    }

    static func target(_ args: [String]) throws -> (String, Int) {
        guard args.count == 2, RepoConfig.isValidSlug(args[0]), let n = Int(args[1]), n > 0, String(n) == args[1] else {
            throw CommandError(usage)
        }
        return (args[0], n)
    }

    /// Re-checks the stored payload, refuses if the PR head moved, then posts it with the same sender as a review.
    static func post(_ paths: Paths, _ slug: String, _ n: Int) throws -> String {
        guard let found = Drafts.newest(paths, slug: slug, n: n) else { throw CommandError("no draft for \(slug) #\(n)") }
        let draft = found.draft
        let view = try PRView.fetch(slug, n)
        guard view.headRefOid == draft.head else {
            var stale = draft
            stale.stale = true
            try Drafts.write(stale, runId: found.runId, paths)
            try markRow(paths, found.runId, slug, n, draft: false, posted: nil)
            throw CommandError(movedMessage(n))
        }
        let me = try GH.run(["api", "user", "--jq", ".login"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let own = view.author?.login.caseInsensitiveCompare(me) == .orderedSame
        let payload = ReviewPayload(commit_id: draft.head, event: draft.event, body: draft.body, comments: draft.comments)
        try ReviewValidator.checkPayload(payload, files: Set(view.files.map(\.path)), own: own)

        let payloadPath = paths.scratchDir + "/\(found.runId)/" + slug.replacingOccurrences(of: "/", with: "-")
            + "/\(n)/payload.json"
        try PRCommands.send(try PRCommands.json(payload), slug: slug, n: n, path: payloadPath)
        try? FileManager.default.removeItem(atPath: found.path)
        try markRow(paths, found.runId, slug, n, draft: false, posted: Date())
        return "posted \(draft.event) on \(slug) #\(n)"
    }

    static func movedMessage(_ n: Int) -> String {
        "PR #\(n) changed since this draft; the next sweep reviews it again"
    }

    static func discard(_ paths: Paths, _ slug: String, _ n: Int) throws -> String {
        guard let found = Drafts.newest(paths, slug: slug, n: n) else { throw CommandError("no draft for \(slug) #\(n)") }
        try FileManager.default.removeItem(atPath: found.path)
        try markRow(paths, found.runId, slug, n, draft: false, posted: nil)
        return "discarded the draft for \(slug) #\(n)"
    }

    /// Clears the row's draft mark in the run it came from. Runs that have finished accept this.
    private static func markRow(_ paths: Paths, _ runId: String, _ slug: String, _ n: Int, draft: Bool, posted: Date?) throws {
        try RunStore(paths: paths).mutate(runId) { $0.setDraft(repo: slug, n: n, draft: draft, posted: posted) }
    }
}
