import Foundation

/// Which header copy to show. Chosen from the snapshot alone, so the choice is testable.
enum HeaderKind: Equatable {
    case notScheduled
    case paused(since: Date?)
    case running(changes: Int, reviewing: Int, total: Int, landed: Int, started: Date?, tokens: Int)
    case failed(message: String)
    case emptyRun(repos: Int, checkedAt: Date, next: Date?)
    case idle(changes: Int, next: Date?)
    case noSweeps(next: Date?)
}

/// One segment of a row's four-part rail.
enum RailSegment: Equatable {
    case done, current, future
}

/// One PR as a row: its order, its phase word, its stamp and its rail.
struct RowModel: Equatable, Identifiable {
    let strip: Strip
    let phase: String?          // "reviewing" and friends, while active
    let rail: [RailSegment]?    // nil for skipped and dropped rows
    var id: String { strip.id }
}

struct RepoGroup: Equatable, Identifiable {
    let repo: String
    let error: String?
    let rows: [RowModel]
    var id: String { repo }
}

enum Presentation {
    static let phaseWords = ["gathering", "reviewing", "checking", "posting"]

    static func headerKind(_ snap: Snapshot, now: Date) -> HeaderKind {
        if !snap.jobInstalled { return .notScheduled }
        let strips = Store.strips(from: snap.run)
        let changes = strips.filter { $0.verdict == .changes }.count
        if snap.running, let run = snap.run {
            return .running(changes: changes, reviewing: strips.filter(\.active).count, total: strips.count,
                            landed: strips.filter { $0.verdict != nil }.count, started: run.started,
                            tokens: run.tokens)
        }
        if snap.paused { return .paused(since: snap.pausedSince) }
        if let run = snap.run, run.finished != nil {
            if let message = failureMessage(run) { return .failed(message: message) }
            if strips.isEmpty {
                return .emptyRun(repos: run.repos.count, checkedAt: run.finished ?? run.started, next: snap.nextRun)
            }
            return .idle(changes: changes, next: snap.nextRun)
        }
        if snap.run == nil { return .noSweeps(next: snap.nextRun) }
        return .idle(changes: changes, next: snap.nextRun)
    }

    /// The first line of the run's error, or of the first repo error. nil when the run had none.
    static func failureMessage(_ run: RunState) -> String? {
        let message = run.error ?? run.repos.compactMap(\.error).first
        return message?.split(separator: "\n").first.map(String.init)
    }

    /// Sort order: needs changes, then in progress (and queued while running), then approved, then skipped,
    /// then dropped. Ties go by PR number, highest first.
    static func rank(_ s: Strip, running: Bool) -> Int {
        if s.verdict == .changes { return 0 }
        if s.active || (running && s.verdict == nil) { return 1 }
        if s.verdict == .approve { return 2 }
        if s.verdict == .skipped { return 3 }
        return 4
    }

    static func rows(from strips: [Strip], running: Bool, repos: [RepoState]) -> [RepoGroup] {
        let order = repos.map(\.slug)
        let uniqueOrder = order.isEmpty ? Array(Set(strips.map(\.repo))).sorted() : order
        return uniqueOrder.map { slug in
            let mine = strips.filter { $0.repo == slug }.sorted { a, b in
                let ra = rank(a, running: running), rb = rank(b, running: running)
                return ra != rb ? ra < rb : a.number > b.number
            }
            return RepoGroup(repo: slug, error: repos.first { $0.slug == slug }?.error,
                             rows: mine.map { row($0, running: running) })
        }
    }

    static func row(_ s: Strip, running: Bool) -> RowModel {
        let phase = s.active && s.verdict == nil ? phaseWords[min(max(s.stage, 1), 4) - 1] : nil
        return RowModel(strip: s, phase: phase, rail: rail(s, running: running))
    }

    static func rail(_ s: Strip, running: Bool) -> [RailSegment]? {
        if s.verdict == .skipped { return nil }
        if s.verdict == nil && !s.active && !running { return nil }   // dropped
        if s.verdict != nil { return [.done, .done, .done, .done] }
        if !s.active { return [.future, .future, .future, .future] }  // queued while running
        let current = min(max(s.stage, 1), 4) - 1
        return (0..<4).map { $0 < current ? .done : ($0 == current ? .current : .future) }
    }

    /// Distance from the radar centre as a fraction of the outer ring: queued sits on the outer ring,
    /// each active phase one step inward, and a PR with a verdict lands at 18%.
    static func progress(_ s: Strip) -> Double {
        if s.verdict != nil { return 0.18 }
        if s.active {
            return [0.8, 0.6, 0.4, 0.3][min(max(s.stage, 1), 4) - 1]
        }
        return 1.0
    }
}
