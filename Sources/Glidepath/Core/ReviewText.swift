import Foundation

/// What a review said, as it was sent (or held as a draft): `<stateDir>/reviews/<runId>/<owner-name>/<n>.json`.
/// `event`, `body` and `comments` are the validated payload GitHub received, so the window shows that text.
/// `posted` is an ISO-8601 time once the review is posted, and null while it is a draft.
struct ReviewTextRecord: Codable, Equatable {
    var event: String
    var body: String
    var comments: [PayloadComment]
    var head: String
    var posted: String?

    enum CodingKeys: String, CodingKey { case event, body, comments, head, posted }

    /// Writes `posted` as null rather than leaving the key out, as the file format promises.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event, forKey: .event)
        try c.encode(body, forKey: .body)
        try c.encode(comments, forKey: .comments)
        try c.encode(head, forKey: .head)
        try c.encode(posted, forKey: .posted)
    }
}

/// The review text store. Text is kept for 90 days and pruned by the runner, so it never grows without limit.
enum ReviewText {
    static let maxAge: TimeInterval = 90 * 24 * 3600

    static func folder(_ paths: Paths, runId: String, slug: String) -> String {
        paths.stateDir + "/reviews/" + runId + "/" + slug.replacingOccurrences(of: "/", with: "-")
    }

    static func path(_ paths: Paths, runId: String, slug: String, n: Int) -> String {
        folder(paths, runId: runId, slug: slug) + "/\(n).json"
    }

    /// Writes the record atomically. Throws on failure; callers decide whether that matters.
    static func write(_ record: ReviewTextRecord, runId: String, slug: String, n: Int, _ paths: Paths) throws {
        let dir = folder(paths, runId: runId, slug: slug)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try RunStore.encoder().encode(record)
        try data.write(to: URL(fileURLWithPath: path(paths, runId: runId, slug: slug, n: n)), options: .atomic)
    }

    /// Writes the record for a post or a draft. A failure goes to stderr and never fails the post.
    static func save(_ record: ReviewTextRecord, runId: String, slug: String, n: Int, _ paths: Paths) {
        do {
            try write(record, runId: runId, slug: slug, n: n, paths)
        } catch {
            eprint("could not record the review text for \(slug) #\(n): \(error)")
        }
    }

    /// The record for one PR in one run, or nil when none was written (reviews from before 1.2, or unreadable files).
    static func read(_ paths: Paths, runId: String, slug: String, n: Int) -> ReviewTextRecord? {
        guard let data = FileManager.default.contents(atPath: path(paths, runId: runId, slug: slug, n: n)) else {
            return nil
        }
        return try? JSONDecoder().decode(ReviewTextRecord.self, from: data)
    }

    /// Deletes `<root>/reviews/<runId>` for runs that started more than `maxAge` before `now`. A run file that is
    /// missing or unreadable falls back to the folder's modification date. Nothing else is touched.
    static func prune(root: String, now: Date, maxAge: TimeInterval = maxAge) {
        let fm = FileManager.default
        let reviews = root + "/reviews"
        for runId in (try? fm.contentsOfDirectory(atPath: reviews)) ?? [] {
            let dir = reviews + "/" + runId
            let modified = (try? fm.attributesOfItem(atPath: dir))?[.modificationDate] as? Date
            guard let started = runStart(root, runId) ?? modified, now.timeIntervalSince(started) > maxAge else { continue }
            try? fm.removeItem(atPath: dir)
        }
    }

    private static func runStart(_ root: String, _ runId: String) -> Date? {
        guard let data = FileManager.default.contents(atPath: root + "/runs/" + runId + ".json"),
              let run = try? RunStore.decoder().decode(RunState.self, from: data) else { return nil }
        return run.started
    }
}
