import Foundation

/// `<stateDir>/drafts/<runId>/<owner-name>/<n>.json`: a review that draft mode held back. `event`, `body` and
/// `comments` are the validated payload, so posting sends what the sweep wrote. `head` is the commit it was
/// reviewed at; posting refuses if the PR has moved.
struct DraftFile: Codable, Equatable {
    var slug: String
    var n: Int
    var head: String
    var event: String
    var body: String
    var comments: [PayloadComment]
    var created: Date
    /// Set when the PR moved after the draft was written. A stale draft is not offered again.
    var stale: Bool? = nil
}

enum Drafts {
    /// A draft found on disk, with the run it came from.
    struct Found {
        let runId: String
        let path: String
        let draft: DraftFile
    }

    static func folder(_ paths: Paths, runId: String, slug: String) -> String {
        paths.stateDir + "/drafts/" + runId + "/" + slug.replacingOccurrences(of: "/", with: "-")
    }

    static func path(_ paths: Paths, runId: String, slug: String, n: Int) -> String {
        folder(paths, runId: runId, slug: slug) + "/\(n).json"
    }

    static func write(_ draft: DraftFile, runId: String, _ paths: Paths) throws {
        let dir = folder(paths, runId: runId, slug: draft.slug)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try RunStore.encoder().encode(draft)
        try data.write(to: URL(fileURLWithPath: path(paths, runId: runId, slug: draft.slug, n: draft.n)), options: .atomic)
    }

    /// Every draft on disk, newest first. Stale ones are included only when `includeStale` is set.
    /// Unreadable files are skipped, and a file whose slug does not match its folder is ignored.
    static func all(_ paths: Paths, includeStale: Bool = false) -> [Found] {
        let fm = FileManager.default
        var out: [Found] = []
        for runId in (try? fm.contentsOfDirectory(atPath: paths.stateDir + "/drafts")) ?? [] {
            let runDir = paths.stateDir + "/drafts/" + runId
            for folder in (try? fm.contentsOfDirectory(atPath: runDir)) ?? [] {
                for file in (try? fm.contentsOfDirectory(atPath: runDir + "/" + folder)) ?? [] where file.hasSuffix(".json") {
                    let path = runDir + "/" + folder + "/" + file
                    guard let data = fm.contents(atPath: path),
                          let draft = try? RunStore.decoder().decode(DraftFile.self, from: data),
                          folder == draft.slug.replacingOccurrences(of: "/", with: "-"),
                          file == "\(draft.n).json" else { continue }
                    if draft.stale == true && !includeStale { continue }
                    out.append(Found(runId: runId, path: path, draft: draft))
                }
            }
        }
        return out.sorted { $0.draft.created > $1.draft.created }
    }

    /// The newest open draft for one PR.
    static func newest(_ paths: Paths, slug: String, n: Int) -> Found? {
        all(paths).first { $0.draft.slug == slug && $0.draft.n == n }
    }
}
