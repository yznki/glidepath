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

    static func new(id: String, now: Date) -> RunState {
        RunState(id: id, started: now, finished: nil, repos: [], tokens: 0, error: nil)
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

    mutating func setRepoError(_ slug: String, _ message: String) {
        let ri = repoIndex(slug)
        repos[ri].error = message
    }

    mutating func addTokens(repo slug: String, n: Int, tokens: Int) {
        guard let ri = repoIndexIfExists(slug), let pi = repos[ri].prs.firstIndex(where: { $0.n == n }) else { return }
        repos[ri].prs[pi].tokens += tokens
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
