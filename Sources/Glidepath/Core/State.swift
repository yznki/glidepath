import Foundation

/// Stage order for a PR inside a run: gather -> review -> check -> post.
enum Stage: String, Codable, CaseIterable, Equatable {
    case gather, review, check, post

    var rank: Int { Stage.allCases.firstIndex(of: self) ?? 0 }
}

enum Verdict: String, Codable, Equatable {
    case approve, changes, skipped
}

struct PRState: Codable, Equatable {
    var n: Int
    var author: String?
    var title: String?
    var stage: Stage
    var active: Bool
    var verdict: Verdict?
    var reason: String?
    var tokens: Int
    /// Head SHA recorded by `pr info` at gather time. Posting refuses if the head has moved since.
    var head: String? = nil
    /// Set when the PR was not reviewed in this sweep and its last result is carried over from an earlier one.
    var carriedFrom: Date? = nil
    /// Optional so 1.0.x run files still decode. True while a draft review waits to be posted.
    var draft: Bool? = nil
    /// When the draft was posted. Set by `glidepath drafts post`.
    var posted: Date? = nil
    /// True when the PR touches a `flag_paths` prefix. The review note says so; the verdict is unchanged.
    var flagged: Bool? = nil
    /// Set on a PR skipped for size: "size". Its row offers Review.
    var skipReason: String? = nil
    /// Additions plus deletions at gather time. Optional for 1.0.x run files.
    var changedLines: Int? = nil
}

struct RepoState: Codable, Equatable {
    var slug: String
    var prs: [PRState]
    var error: String?
}

/// `~/.local/state/glidepath/runs/<id>.json`. The CLI owns this schema; the model only calls
/// `glidepath state set`, which goes through the transitions below.
struct RunState: Codable, Equatable {
    var id: String
    var started: Date
    var finished: Date?
    var repos: [RepoState]
    var tokens: Int
    var error: String?
    /// "review" for `glidepath review` (one PR, by hand). nil for a sweep. Optional so older run files decode.
    var kind: String? = nil

    static func new(id: String, now: Date, kind: String? = nil) -> RunState {
        RunState(id: id, started: now, finished: nil, repos: [], tokens: 0, error: nil, kind: kind)
    }

    /// A review run starts from the rows of the run it replaces, so the popover keeps the last sweep's results.
    /// Rows for `target` (the PR this run reviews) are left out; this run writes them. Carried rows keep their
    /// verdict and reason, and show when they were decided, as rows carried over from a failed run do.
    mutating func carryRows(from previous: RunState, except target: (slug: String, n: Int)?) {
        for repo in previous.repos {
            for old in repo.prs {
                if let target, target.slug == repo.slug, target.n == old.n { continue }
                let ri = repoIndex(repo.slug)
                guard !repos[ri].prs.contains(where: { $0.n == old.n }) else { continue }
                var row = old
                row.active = false
                row.carriedFrom = old.carriedFrom ?? previous.started
                repos[ri].prs.append(row)
            }
        }
    }

    /// The popover's view of held drafts: every open draft on disk shows, whichever run wrote it. Its row gets the
    /// draft mark, and a draft with no row gets one, so it can still be posted after its run was replaced.
    /// Only the in-memory copy changes; nothing is saved.
    mutating func showDrafts(_ found: [Drafts.Found]) {
        for ri in repos.indices {
            for pi in repos[ri].prs.indices {
                let n = repos[ri].prs[pi].n
                repos[ri].prs[pi].draft = found.contains { $0.draft.slug == repos[ri].slug && $0.draft.n == n }
            }
        }
        for item in found {
            let d = item.draft
            let listed = repos.first { $0.slug == d.slug }?.prs.contains { $0.n == d.n } ?? false
            guard !listed else { continue }
            let ri = repoIndex(d.slug)
            repos[ri].prs.append(PRState(n: d.n, author: d.author, title: d.title, stage: .post, active: false,
                                         verdict: d.event == "APPROVE" ? .approve : .changes, reason: nil, tokens: 0,
                                         draft: true))
        }
    }

    /// Applies one stage transition for a PR. Stages only move forward, and a verdict is final.
    mutating func setPR(repo slug: String, n: Int, stage: Stage?, author: String?, title: String?,
                        verdict: Verdict?, reason: String?) throws {
        guard finished == nil else { throw StateError("run \(id) has already finished") }
        let ri = repoIndex(slug)
        if let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) {
            var pr = repos[ri].prs[pi]
            if let existing = pr.verdict {
                // Stamped PRs stay stamped: only the same verdict again is accepted.
                guard verdict == existing, stage == nil || stage == pr.stage else {
                    throw StateError("\(slug)#\(n) already has verdict \(existing.rawValue)")
                }
                return
            }
            if let stage {
                guard stage.rank >= pr.stage.rank else {
                    throw StateError("\(slug)#\(n): stage cannot move back from \(pr.stage.rawValue) to \(stage.rawValue)")
                }
                pr.stage = stage
            }
            pr.author = author ?? pr.author
            pr.title = title ?? pr.title
            apply(verdict: verdict, reason: reason, to: &pr)
            repos[ri].prs[pi] = pr
        } else {
            var pr = PRState(n: n, author: author, title: title, stage: stage ?? .gather,
                             active: true, verdict: nil, reason: nil, tokens: 0)
            apply(verdict: verdict, reason: reason, to: &pr)
            repos[ri].prs.append(pr)
        }
    }

    private func repoIndexIfExists(_ slug: String) -> Int? {
        repos.firstIndex(where: { $0.slug == slug })
    }

    private mutating func repoIndex(_ slug: String) -> Int {
        if let i = repoIndexIfExists(slug) { return i }
        repos.append(RepoState(slug: slug, prs: [], error: nil))
        return repos.count - 1
    }

    private func apply(verdict: Verdict?, reason: String?, to pr: inout PRState) {
        if let verdict {
            pr.verdict = verdict
            pr.reason = reason ?? pr.reason
            pr.active = false
        } else {
            pr.active = true
        }
    }

    mutating func ensureRepo(_ slug: String) {
        _ = repoIndex(slug)
    }

    /// A progress note on a PR that has no verdict yet.
    mutating func setNote(repo slug: String, n: Int, note: String) throws {
        guard let ri = repos.firstIndex(where: { $0.slug == slug }),
              let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else {
            throw StateError("unknown PR for this run: \(slug) #\(n)")
        }
        repos[ri].prs[pi].reason = note
    }

    mutating func recordHead(repo slug: String, n: Int, head: String) throws {
        guard let ri = repos.firstIndex(where: { $0.slug == slug }),
              let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else {
            throw StateError("unknown PR for this run: \(slug) #\(n)")
        }
        repos[ri].prs[pi].head = head
    }

    /// Marks a row as a held draft, or clears the mark once the draft is posted or discarded. Works after the run
    /// has finished, because drafts are posted later from the app or the CLI.
    mutating func setDraft(repo slug: String, n: Int, draft: Bool, posted: Date?) {
        guard let ri = repoIndexIfExists(slug), let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else { return }
        repos[ri].prs[pi].draft = draft
        repos[ri].prs[pi].posted = posted ?? repos[ri].prs[pi].posted
    }

    /// Records the PR's size, and whether it was skipped for size. Missing rows are left alone.
    mutating func setSize(repo slug: String, n: Int, changedLines: Int, skippedForSize: Bool) {
        guard let ri = repoIndexIfExists(slug), let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else { return }
        repos[ri].prs[pi].changedLines = changedLines
        repos[ri].prs[pi].skipReason = skippedForSize ? "size" : nil
    }

    mutating func setFlagged(repo slug: String, n: Int) throws {
        guard let ri = repoIndexIfExists(slug), let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else {
            throw StateError("unknown PR for this run: \(slug) #\(n)")
        }
        repos[ri].prs[pi].flagged = true
    }

    mutating func setRepoError(_ slug: String, _ message: String) {
        let ri = repoIndex(slug)
        repos[ri].error = message
    }

    mutating func addTokens(repo slug: String, n: Int, tokens: Int) {
        guard let ri = repoIndexIfExists(slug), let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else { return }
        repos[ri].prs[pi].tokens += tokens
    }

    /// After a failed sweep, a PR with no verdict in this run takes the verdict of the newest earlier run that
    /// had one. It carries that run's start, or the start it was carried from, so the row says when it was decided.
    /// ponytail: scans every earlier run in memory; index the runs if the folder ever grows large.
    mutating func carryOver(from earlier: [RunState]) {
        let newest = earlier.filter { $0.id != id }.sorted { $0.started > $1.started }
        for ri in repos.indices {
            let slug = repos[ri].slug
            for pi in repos[ri].prs.indices where repos[ri].prs[pi].verdict == nil {
                let n = repos[ri].prs[pi].n
                for run in newest {
                    guard let old = run.repos.first(where: { $0.slug == slug })?.prs.first(where: { $0.n == n }),
                          let verdict = old.verdict else { continue }
                    repos[ri].prs[pi].verdict = verdict
                    repos[ri].prs[pi].reason = old.reason
                    repos[ri].prs[pi].carriedFrom = old.carriedFrom ?? run.started
                    break
                }
            }
        }
    }

    mutating func finish(at now: Date, error: String?) {
        finished = now
        self.error = error
        for ri in repos.indices {
            for pi in repos[ri].prs.indices { repos[ri].prs[pi].active = false }
        }
    }
}

struct StateError: Error, CustomStringConvertible, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Reads and writes run files and the `current` symlink. Every write is atomic.
struct RunStore {
    let paths: Paths

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func save(_ run: RunState) throws {
        try FileManager.default.createDirectory(atPath: paths.runsDir, withIntermediateDirectories: true)
        let data = try RunStore.encoder().encode(run)
        // `.atomic` writes a temp file in the same folder and renames it over the target.
        try data.write(to: URL(fileURLWithPath: paths.runFile(run.id)), options: .atomic)
    }

    /// Read-modify-write under `state.lock`, so concurrent writers (the runner and the review
    /// skill's `state set` calls) cannot overwrite each other's changes.
    func mutate(_ id: String, _ body: (inout RunState) throws -> Void) throws {
        try FileManager.default.createDirectory(atPath: paths.stateDir, withIntermediateDirectories: true)
        let fd = open(paths.stateDir + "/state.lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw StateError("cannot open state lock") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StateError("cannot lock state") }
        defer { flock(fd, LOCK_UN) }
        var run = try load(id)
        try body(&run)
        try save(run)
    }

    /// Every readable run on disk. Unreadable files are skipped.
    func loadAll() -> [RunState] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: paths.runsDir)) ?? []
        return files.filter { $0.hasSuffix(".json") }.compactMap { try? load(String($0.dropLast(5))) }
    }

    func load(_ id: String) throws -> RunState {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.runFile(id)))
        return try RunStore.decoder().decode(RunState.self, from: data)
    }

    /// The run `current` points at, or nil when there is none yet.
    func loadCurrent() throws -> RunState? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: paths.currentLink) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.stateDir + "/" + target))
        return try RunStore.decoder().decode(RunState.self, from: data)
    }

    /// Points `current` at a run by replacing the symlink with a rename, so readers never see a gap.
    func makeCurrent(_ id: String) throws {
        let tmp = paths.stateDir + "/.current.tmp"
        try? FileManager.default.removeItem(atPath: tmp)
        try FileManager.default.createSymbolicLink(atPath: tmp, withDestinationPath: "runs/\(id).json")
        guard rename(tmp, paths.currentLink) == 0 else {
            throw StateError("could not move current to run \(id)")
        }
    }
}

/// Exclusive run lock (flock). Released by the kernel if the process dies, so a crashed run
/// never looks like it is still going.
final class RunLock {
    private let fd: Int32

    private init(fd: Int32) { self.fd = fd }

    static func acquire(_ path: String) throws -> RunLock? {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw StateError("cannot open lock file \(path)") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        return RunLock(fd: fd)
    }

    static func isHeld(_ path: String) -> Bool {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

/// The Schedule section's "This week" counts. Rows carried over from an earlier run are left out, so a PR counts once,
/// in the run that decided it. Pure: the caller passes the runs.
struct WeekStats: Equatable {
    var reviews = 0
    var needChanges = 0
    var tokens = 0

    static func compute(runs: [RunState], since: Date) -> WeekStats {
        var out = WeekStats()
        for run in runs where run.started >= since {
            out.tokens += run.tokens
            for repo in run.repos {
                for pr in repo.prs where pr.carriedFrom == nil {
                    switch pr.verdict {
                    case .approve?: out.reviews += 1
                    case .changes?:
                        out.reviews += 1
                        out.needChanges += 1
                    case .skipped?, nil: break
                    }
                }
            }
        }
        return out
    }

    /// Monday 00:00 in the calendar's time zone, of the week that holds `date`.
    static func weekStart(of date: Date, calendar: Calendar = .current) -> Date? {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
