import Foundation

/// The header copy for each state (docs/design.md, section 2). Pure, so the copy is testable.
struct HeaderCopy: Equatable {
    enum Tone: Equatable {
        case ink, secondary, tertiary, changes, error
    }
    var headline: String
    var headlineTone: Tone = .ink
    var line2: String?
    var line2Tone: Tone = .ink
    var line2Weight: Int = 400
    var line3: String?
    var line3Tone: Tone = .secondary
    /// "Open log" follows line 3 as a link.
    var openLog = false

    /// `drafts` is the number of reviews waiting to be posted. Idle copy gives way to that count when it is not zero.
    static func make(_ kind: HeaderKind, now: Date, drafts: Int = 0) -> HeaderCopy {
        switch kind {
        case .notScheduled:
            return HeaderCopy(headline: "Not scheduled", headlineTone: .changes,
                              line2: "Run `glidepath init` to set it up")
        case .paused(let since, let lastStarted):
            let last = lastStarted.map { "Last sweep \(clock($0)) · scheduled sweeps skipped" }
                ?? "Scheduled sweeps are skipped"
            return HeaderCopy(headline: "Paused", headlineTone: .changes, line2: last,
                              line3: since.map { "Paused since \(clock($0))" }, line3Tone: .tertiary)
        case .running(let changes, let inFlight, _, let landed, let started):
            var copy = HeaderCopy(headline: "\(inFlight) in flight, \(landed) landed",
                                  line3: started.map { "Started \(clock($0))" }, line3Tone: .tertiary)
            if changes > 0 {
                copy.line2 = "\(changes) need changes"
                copy.line2Tone = .changes
                copy.line2Weight = 500
            }
            return copy
        case .preparing(let phase, let started):
            return HeaderCopy(headline: "Getting ready", line2: Presentation.preparingLine(phase),
                              line3: started.map { "Started \(clock($0))" }, line3Tone: .tertiary)
        case .failed(let reason, let started, let next):
            let retry = next.map { "Retrying at \(clock($0)) · " } ?? ""
            _ = started
            return HeaderCopy(headline: "Last sweep failed", headlineTone: .error,
                              line2: reason, line3: retry, line3Tone: .tertiary, openLog: true)
        case .emptyRun(let repos, let next, let lastStarted):
            let last = lastStarted.map { " · last sweep \(clock($0))" } ?? ""
            return HeaderCopy(headline: "No open PRs",
                              line2: "Watching \(repos) repo\(repos == 1 ? "" : "s")\(last)",
                              line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" }, line3Tone: .tertiary)
        case .idle(let changes, let next, let lastStarted, let total):
            let count = "\(total) PR\(total == 1 ? "" : "s")"
            let last = lastStarted.map { "Last sweep \(clock($0)) · \(count)" } ?? count
            var copy = HeaderCopy(headline: changes > 0 ? "\(changes) need changes" : "All clear",
                                  line2: last,
                                  line3: next.map { "Next sweep \(clock($0)), in \(untilText($0, now))" } ?? "No sweep scheduled",
                                  line3Tone: .tertiary)
            if drafts > 0 {
                copy.headline = "\(drafts) waiting for you"
                copy.headlineTone = .ink
                copy.line2 = nil
            }
            return copy
        case .dryRun:
            return HeaderCopy(headline: "Dry run in progress", line2: "Nothing is posted. Watch it in Glidepath.",
                              line2Tone: .secondary)
        case .notConfigured(let next):
            return HeaderCopy(headline: "Ready for the first sweep",
                              line2: "Pick the repos Glidepath should review.",
                              line3: next.map { "First sweep at \(clock($0))" }, line3Tone: .tertiary)
        case .noSweeps(let next, let repos):
            return HeaderCopy(headline: "Ready for the first sweep",
                              line2: "Watching \(repos) repo\(repos == 1 ? "" : "s")",
                              line3: next.map { "First sweep at \(clock($0)), in \(untilText($0, now))" }
                                  ?? "No sweep scheduled",
                              line3Tone: .tertiary)
        }
    }

    /// Locale time: the user's format, 12 or 24 hour as the system has it.
    static func clock(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }

    static func untilText(_ next: Date, _ now: Date) -> String {
        let mins = max(0, Int(next.timeIntervalSince(now) / 60))
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}
