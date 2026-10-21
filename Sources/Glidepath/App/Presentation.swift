import Foundation

/// Which header copy to show (docs/design.md, section 2). Chosen from the snapshot alone, so it is testable.
enum HeaderKind: Equatable {
    case notScheduled
    case paused(since: Date?, lastStarted: Date?)
    case running(changes: Int, reviewing: Int, total: Int, landed: Int, started: Date?)
    case failed(reason: String, started: Date?, next: Date?)
    case emptyRun(repos: Int, next: Date?, lastStarted: Date?)
    case idle(changes: Int, next: Date?, lastStarted: Date?, total: Int)
    case noSweeps(next: Date?, repos: Int)
}

/// The status idiom of a row (docs/design.md, section 3): a shape and a label, one per row.
enum RowStatus: Equatable {
    case changes                       // triangle, "Changes"
    case approved                      // circle, "Approved"
    case skipped(reason: String?)      // dash, "Skipped"
    case noResult                      // hollow circle, "No result"
    case active(phase: String)         // hollow blue circle, the stage word, and a meter
    case queued                        // hollow grey circle, "Queued"
}

/// One segment of the four-dash meter.
enum MeterSegment: Equatable {
    case done, current, future
}

/// One PR as a row.
struct RowModel: Equatable, Identifiable {
    let strip: Strip
    let status: RowStatus
    let meter: [MeterSegment]?
    var id: String { strip.id }
}

struct RepoGroup: Equatable, Identifiable {
    let repo: String
    let error: String?
    let rows: [RowModel]
    var id: String { repo }
}

enum Presentation {
    /// Stage words in the status idiom, capitalised, and as the profile's stage labels.
    static let phaseWords = ["Gathering", "Reviewing", "Checking", "Landing"]

    static func headerKind(_ snap: Snapshot, now: Date) -> HeaderKind {
        if !snap.jobInstalled { return .notScheduled }
        let strips = Store.strips(from: snap.run)
        let changes = strips.filter { $0.verdict == .changes }.count
        if snap.running, let run = snap.run {
            return .running(changes: changes, reviewing: strips.filter { $0.active && $0.verdict == nil }.count,
                            total: strips.count, landed: strips.filter { $0.verdict != nil }.count,
                            started: run.started)
        }
        if snap.paused {
            return .paused(since: snap.pausedSince, lastStarted: snap.run?.started)
        }
        if let run = snap.run, run.finished != nil {
            if let message = failureMessage(run) {
                return .failed(reason: plainFailure(message), started: run.started, next: snap.nextRun)
            }
            if strips.isEmpty {
                return .emptyRun(repos: run.repos.count, next: snap.nextRun, lastStarted: run.started)
            }
            return .idle(changes: changes, next: snap.nextRun, lastStarted: run.started, total: strips.count)
        }
        if snap.run == nil { return .noSweeps(next: snap.nextRun, repos: snap.repoCount) }
        return .idle(changes: changes, next: snap.nextRun, lastStarted: snap.run?.started, total: strips.count)
    }

    /// The first line of the run's error, or of the first repo error. nil when the run had none.
    static func failureMessage(_ run: RunState) -> String? {
        let message = run.error ?? run.repos.compactMap(\.error).first
        return message?.split(separator: "\n").first.map(String.init)
    }

    /// The run error in plain words for the header. "claude exited 1: ..." becomes a sentence about the agent.
    static func plainFailure(_ message: String) -> String {
        if let range = message.range(of: #"claude exited (\d+)"#, options: .regularExpression) {
            let code = message[range].replacingOccurrences(of: "claude exited ", with: "")
            return "The review agent stopped early (exit \(code))"
        }
        return message
    }

    /// Sort order: needs changes, then in progress (and queued while running), then approved, then skipped,
    /// then no result. Ties go by PR number, highest first.
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
        RowModel(strip: s, status: status(s, running: running), meter: meter(s))
    }

    static func status(_ s: Strip, running: Bool) -> RowStatus {
        switch s.verdict {
        case .changes?: return .changes
        case .approve?: return .approved
        case .skipped?: return .skipped(reason: s.reason)
        case nil:
            if s.active { return .active(phase: phaseWords[min(max(s.stage, 1), 4) - 1]) }
            return running ? .queued : .noResult
        }
    }

    /// The four dashes: done segments before the current stage, the current one in the system blue. Only
    /// active rows have a meter.
    static func meter(_ s: Strip) -> [MeterSegment]? {
        guard s.active, s.verdict == nil else { return nil }
        let current = min(max(s.stage, 1), 4) - 1
        return (0..<4).map { $0 < current ? .done : ($0 == current ? .current : .future) }
    }

    /// Profile marks in display order. Each in-flight mark is labelled with its PR number.
    static func marks(_ groups: [RepoGroup], running: Bool) -> [ProfileMark] {
        groups.flatMap(\.rows).map { row in
            let s = row.strip
            let kind: MarkKind
            if let verdict = s.verdict {
                kind = .landed(verdict)
            } else if s.active {
                kind = .active(stage: min(max(s.stage, 1), 4))
            } else if running {
                kind = .queued
            } else {
                kind = .dropped
            }
            return ProfileMark(id: s.id, kind: kind, label: "#\(s.number)")
        }
    }
}
