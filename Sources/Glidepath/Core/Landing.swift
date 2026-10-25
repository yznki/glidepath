import Foundation

/// A merge Glidepath made, or one whose main checks are still being watched. One entry per merge, in `tend/landed.json`.
struct TendLanded: Codable, Equatable {
    var slug: String
    var n: Int
    var title: String
    /// The merge commit on the default branch.
    var sha: String
    /// The commit before it on the default branch.
    var parent: String
    var at: Date
    /// "watching", "ok", "broke", "reverted" or "timeout".
    var status: String
    /// Checks that failed on the merge commit and passed on the commit before it.
    var failing: [String] = []
    /// The revert PR's number, once one is open.
    var revert: Int?
}

extension TendLanded {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        n = try c.decode(Int.self, forKey: .n)
        title = try c.decode(String.self, forKey: .title)
        sha = try c.decode(String.self, forKey: .sha)
        parent = try c.decode(String.self, forKey: .parent)
        at = try c.decode(Date.self, forKey: .at)
        status = try c.decode(String.self, forKey: .status)
        failing = try c.decodeIfPresent([String].self, forKey: .failing) ?? []
        revert = try c.decodeIfPresent(Int.self, forKey: .revert)
    }
}

extension TendStore {
    /// Landed records in the order they were saved. Empty when there are none.
    func loadLanded() -> [TendLanded] {
        guard let data = FileManager.default.contents(atPath: dir + "/landed.json") else { return [] }
        return (try? RunStore.decoder().decode([TendLanded].self, from: data)) ?? []
    }

    /// Writes the records, dropping any landed more than 7 days ago.
    func saveLanded(_ records: [TendLanded]) throws {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        try write(RunStore.encoder().encode(records.filter { $0.at >= cutoff }), to: dir + "/landed.json")
    }
}

/// Whether a ready PR can land, and what the merge means for the PRs stacked on it.
enum Landing {
    /// The PR is approved and clean, not from a fork, tending may act on it, nothing waits on the user, and it targets the
    /// default branch.
    static func ready(_ pr: OpenPR, _ state: TendPR?) -> Bool {
        !pr.isFork && Approach.marker(pr) == 3 && Approach.tendable(pr, state) && state?.held == nil && state?.stuck == nil
            && (state?.calls.isEmpty ?? true) && pr.base == pr.defaultBranch
    }

    /// The lowest-numbered ready PR. One landing per repo per check: main moves, so the next waits for a fresh read.
    static func next(_ prs: [OpenPR], states: [Int: TendPR]) -> OpenPR? {
        prs.filter { ready($0, states[$0.n]) }.min { $0.n < $1.n }
    }

    /// The PRs whose base is `pr`'s branch, lowest number first.
    static func children(of pr: OpenPR, in prs: [OpenPR]) -> [OpenPR] {
        prs.filter { $0.base == pr.branch }.sorted { $0.n < $1.n }
    }

    /// "Ready to land · approved · 4 checks green", then " · then #a, #b" for the PRs stacked above it.
    static func detail(_ pr: OpenPR, _ prs: [OpenPR]) -> String {
        var parts = ["Ready to land", "approved"]
        let green = pr.checks.filter { ["SUCCESS", "NEUTRAL", "SKIPPED"].contains($0.conclusion ?? "") }.count
        if !pr.checks.isEmpty { parts.append("\(green) checks green") }
        if let lane = Approach.lanes(prs).first(where: { $0.contains { $0.n == pr.n } }),
           let at = lane.firstIndex(where: { $0.n == pr.n }), at + 1 < lane.count {
            parts.append("then " + lane[(at + 1)...].map { "#\($0.n)" }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// The body of a revert PR for a landed PR that broke main.
    static func revertBody(n: Int, sha: String, failing: [String]) -> String {
        "Reverts #\(n) (`\(sha.prefix(7))`). \(failing.joined(separator: ", ")) failed on the merge commit and passed on the commit before it."
    }
}

enum WatchVerdict: Equatable {
    case pending
    case ok
    case broke([String])
}

enum MainWatch {
    /// Broke when a check failed (FAILURE or TIMED_OUT) on the merge commit and passed on its parent; a check that failed
    /// on both is not a break, and a cancelled one is not a failure. Pending until every check on the merge commit has
    /// completed, or while none has appeared yet. Otherwise ok.
    static func verdict(merge: [CheckState], parent: [CheckState]) -> WatchVerdict {
        if merge.isEmpty || merge.contains(where: { $0.status != "COMPLETED" }) { return .pending }
        let passedOnParent = Set(parent.filter { $0.conclusion == "SUCCESS" }.map(\.name))
        let broke = merge.filter { ["FAILURE", "TIMED_OUT"].contains($0.conclusion ?? "") && passedOnParent.contains($0.name) }
            .map(\.name)
        return broke.isEmpty ? .ok : .broke(broke)
    }
}

extension Approach {
    /// A landed PR on the runway: phase landed, marker 4. Its label says what happened since.
    static func landedPlane(_ record: TendLanded, lane: Int) -> ApproachPlane {
        let label: String
        switch record.status {
        case "watching": label = "Landed · watching main"
        case "broke": label = "Main broke after #\(record.n)"
        case "reverted": label = record.revert.map { "Reverted in #\($0)" } ?? "Reverted"
        default: label = "Landed"
        }
        return ApproachPlane(slug: record.slug, n: record.n, title: record.title,
                             url: "https://github.com/\(record.slug)/pull/\(record.n)", phase: .landed, marker: 4,
                             label: label, waitingOn: nil, lane: lane, stackIndex: nil, off: false, gates: [], ci: "passed",
                             landedAt: record.at)
    }

    /// The Needs item for a landed PR that broke main and has no revert yet. Nil otherwise.
    static func revertNeed(_ record: TendLanded) -> NeedsItem? {
        guard record.status == "broke", record.revert == nil else { return nil }
        return NeedsItem(id: "\(record.slug)#\(record.n)/revert", slug: record.slug, n: record.n, title: record.title,
                         kind: "revert", detail: "Main broke after #\(record.n) · \(record.failing.joined(separator: ", "))")
    }
}
