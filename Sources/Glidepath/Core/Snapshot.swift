import Foundation

/// One PR as the popover and the radar draw it.
struct Strip: Identifiable, Equatable {
    let repo: String
    let number: Int
    var author: String?
    var title: String?
    var reason: String?
    var stage: Int          // 1...4: gather, review, check, post
    var active: Bool
    var verdict: Verdict?
    var tokens: Int
    var carriedFrom: Date? = nil
    var draft = false
    var flagged = false
    /// A draft post or discard is running for this row: the status reads "Posting…" or "Discarding…".
    var draftAction: DraftAction? = nil
    var posting: Bool { draftAction == .posting }
    /// The last draft post or discard failed: its last output line, shown on line 3.
    var draftError: String? = nil
    /// "size" on a PR skipped for size: its row offers Review.
    var skipReason: String? = nil
    var changedLines: Int? = nil
    /// GitHub lists the PR as a draft. Not the same as `draft`, which marks a held review on disk.
    var isDraftPR = false

    var id: String { "\(repo)#\(number)" }
}

/// A draft command the app is running for one row.
enum DraftAction: Equatable {
    case posting, discarding
}

/// The menu bar app's own update work. `updating` runs `glidepath update --wait`; `failed` stays until the next try.
enum UpdatePhase: Equatable {
    case idle, updating, failed
}

/// Everything the popover shows. `Store` fills it from disk; snapshot rendering fills it with fixtures.
struct Snapshot {
    var run: RunState?
    var running = false
    /// A dry run holds the lock but is not the current run (dry runs never become current).
    var dryRunning = false
    /// The dry run's run file while it holds the lock. Snapshot-only fixtures set it directly.
    var dryRun: RunState?
    var paused = false
    var pausedSince: Date?
    var jobInstalled = true
    var nextRun: Date?
    /// Snapshot rendering only: the clock the window reads for "in 2 h 41 min", in place of Date().
    var now: Date?
    var postsReviews = false
    var schedule: [ScheduleTime] = []
    var repoCount = 0
    /// The parsed config, for the Repos section. Nil when there is no config or it does not parse.
    var config: Config?
    /// `max_changed_lines`, for the Review warning.
    var maxChangedLines = 3000
    var hovered: String?
    /// The cached latest release. The popover offers it when it is newer than this build.
    var update: UpdateCache?
    var checkUpdates = true
    var updateChecking = false
    var updatePhase: UpdatePhase = .idle
    /// The result of "Check for updates…", shown for 4 s.
    var updateNote: String?
    /// Snapshot rendering only: the runs the window reads in place of the run files. Nil in the live app.
    var runs: [RunState]?
    /// Snapshot rendering only: review text by "runId|repo#n", in place of the text store.
    var reviewTexts: [String: ReviewTextRecord] = [:]
    /// Snapshot rendering only: the tool checks Settings shows, in place of running them.
    var tools: [Checks.Item]?
    /// Snapshot rendering only: the login item state, in place of reading it.
    var loginOn = false
    /// Tending is on in config.toml.
    var tendOn = false
    /// What tend's last sweep saw, from `stateDir/tend/approach.json`. Nil until tend has written it.
    var approach: ApproachSnapshot?
    /// The newest 30 tower lines, newest first.
    var tower: [TowerLine] = []
    /// The user's calls by `NeedsItem.id`, read from each PR's tend state: who asked, and the draft reply if any.
    var calls: [String: YourCall] = [:]
    /// Tend rounds started today, from the run files.
    var tendRounds: [RunState] = []
    /// The PRs tend landed, from `tend/landed.json`: watched, ok, broke or reverted.
    var landed: [TendLanded] = []
    /// When the app first saw each landed PR, by `ApproachPlane.id`. The chart glides a plane in once, from its first
    /// sighting. Snapshot rendering sets it directly.
    var landedSeen: [String: Date] = [:]
    /// Snapshot rendering only: the playbooks by repo, in place of reading them.
    var playbooks: [String: Playbook] = [:]
    /// The morning briefing from `tend/briefing.json`, when tend has written one.
    var briefing: Briefing?
    /// Each approach plane's tend state, by `ApproachPlane.id`: its changes since review, and when each reviewer was pinged.
    var prStates: [String: TendPR] = [:]
    /// Each approach plane's split plan, by `ApproachPlane.id`, from `tend/split/`. Only planes that have one.
    var splits: [String: SplitPlan] = [:]
    /// Snapshot rendering only: whether a Linear key is saved, in place of reading the Keychain. Nil in the live app.
    var linearKey: Bool?
}
