import Foundation

/// A fix held for the user to push or discard. `commit` is the local commit's SHA.
struct TendHeld: Codable, Equatable {
    var commit: String
    var summary: String
    var at: Date
    /// The commands the fix session reported as passing. Kept so the playbook can count them once the fix is pushed.
    var ran: [String]? = nil
    /// Agreed thread replies waiting to post when the fix is pushed.
    var replies: [PendingReply] = []
}

/// A reply tend has drafted or agreed to post. `askId` is the ask it answers; `resolve` closes its thread after. A
/// `fixed` reply is the agreed text without its "Fixed in" line: that line is built with the pushed head when it posts.
struct PendingReply: Codable, Equatable {
    var askId: String
    var kind: String
    var body: String
    var resolve: Bool
    var fixed = false
    /// The ask itself: its reviewer to ask again, and the call it becomes when the reply cannot post.
    var ask: Ask? = nil
}

extension PendingReply {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        askId = try c.decode(String.self, forKey: .askId)
        kind = try c.decode(String.self, forKey: .kind)
        body = try c.decode(String.self, forKey: .body)
        resolve = try c.decode(Bool.self, forKey: .resolve)
        fixed = try c.decodeIfPresent(Bool.self, forKey: .fixed) ?? false
        ask = try c.decodeIfPresent(Ask.self, forKey: .ask)
    }
}

extension TendHeld {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commit = try c.decode(String.self, forKey: .commit)
        summary = try c.decode(String.self, forKey: .summary)
        at = try c.decode(Date.self, forKey: .at)
        ran = try c.decodeIfPresent([String].self, forKey: .ran)
        replies = try c.decodeIfPresent([PendingReply].self, forKey: .replies) ?? []
    }
}

/// A question tend could not answer alone: the user decides. `draft` is the reply tend wrote for it, if any.
struct YourCall: Codable, Equatable {
    var id: String
    var kind: String
    var author: String
    /// The first 160 characters of the ask.
    var quote: String
    var draft: String?
    var at: Date
}

/// Glidepath's own review of one PR head. `verdict` is "clean" or "changes"; `done` is set once its findings were handled.
struct SelfReview: Codable, Equatable {
    var head: String
    var at: Date
    var verdict: String
    var findings: [DraftComment]
    var done: Bool
}

/// What tend knows about one PR, in `stateDir/tend/<owner>-<name>-<n>.json`. Only `slug` and `n` are required; a
/// file from an older version loads with the defaults for the rest.
struct TendPR: Codable, Equatable {
    var slug: String
    var n: Int
    /// `Fingerprint.ci` of the checks the last round saw.
    var fingerprint: String?
    var roundsToday = 0
    var roundsDate: Date?
    var triesByHead: [String: Int] = [:]
    var rerunsByHead: [String: Int] = [:]
    var held: TendHeld?
    /// The reason a PR stopped. Cleared when the PR moves to a new head.
    var stuck: String?
    /// Tending is switched off for this PR.
    var off = false
    var pendingRan: [String] = []
    var pendingRanHead: String?
    var lastRound: Date?
    /// Ask ids tend has handled: reviews and comments it answered.
    var answered: [String] = []
    /// Thread ids tend resolved after an agreed fix or a posted reply.
    var resolvedByUs: [String] = []
    /// Asks waiting for the user.
    var calls: [YourCall] = []
    /// Reviewers asked to review again in the last round.
    var rereq: [String] = []
    /// Asks tend has handled, by ask id: a thread's last comment id, or "" for a review or comment. A newer comment on a
    /// thread makes it actionable again.
    var handled: [String: String] = [:]
    /// Set once the PR's reviews and plain comments so far were marked answered: tend works on what comes after.
    var seeded = false
    /// The last self-review of this PR's head.
    var selfReview: SelfReview?
    /// When a self-review that did not run may be tried again. Optional so older files decode.
    var selfReviewRetry: Date?
    /// Whether the PR was a draft at the last check.
    var wasDraft = false
    /// Lines for the PR description's "Changes since review" block.
    var changes: [String] = []
    /// When a reviewer was last pinged, by login.
    var pinged: [String: Date] = [:]
    /// Linear issue ids a comment was posted to for this PR.
    var linearPosted: [String] = []

    init(slug: String, n: Int) {
        self.slug = slug
        self.n = n
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        n = try c.decode(Int.self, forKey: .n)
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint)
        roundsToday = try c.decodeIfPresent(Int.self, forKey: .roundsToday) ?? 0
        roundsDate = try c.decodeIfPresent(Date.self, forKey: .roundsDate)
        triesByHead = try c.decodeIfPresent([String: Int].self, forKey: .triesByHead) ?? [:]
        rerunsByHead = try c.decodeIfPresent([String: Int].self, forKey: .rerunsByHead) ?? [:]
        held = try c.decodeIfPresent(TendHeld.self, forKey: .held)
        stuck = try c.decodeIfPresent(String.self, forKey: .stuck)
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        pendingRan = try c.decodeIfPresent([String].self, forKey: .pendingRan) ?? []
        pendingRanHead = try c.decodeIfPresent(String.self, forKey: .pendingRanHead)
        lastRound = try c.decodeIfPresent(Date.self, forKey: .lastRound)
        answered = try c.decodeIfPresent([String].self, forKey: .answered) ?? []
        resolvedByUs = try c.decodeIfPresent([String].self, forKey: .resolvedByUs) ?? []
        calls = try c.decodeIfPresent([YourCall].self, forKey: .calls) ?? []
        rereq = try c.decodeIfPresent([String].self, forKey: .rereq) ?? []
        handled = try c.decodeIfPresent([String: String].self, forKey: .handled) ?? [:]
        seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
        selfReview = try c.decodeIfPresent(SelfReview.self, forKey: .selfReview)
        selfReviewRetry = try c.decodeIfPresent(Date.self, forKey: .selfReviewRetry)
        wasDraft = try c.decodeIfPresent(Bool.self, forKey: .wasDraft) ?? false
        changes = try c.decodeIfPresent([String].self, forKey: .changes) ?? []
        pinged = try c.decodeIfPresent([String: Date].self, forKey: .pinged) ?? [:]
        linearPosted = try c.decodeIfPresent([String].self, forKey: .linearPosted) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case slug, n, fingerprint, roundsToday, roundsDate, triesByHead, rerunsByHead, held, stuck, off
        case pendingRan, pendingRanHead, lastRound, answered, resolvedByUs, calls, rereq, handled, seeded
        case selfReview, selfReviewRetry, wasDraft, changes, pinged, linearPosted
    }

    /// Marks the PR's reviews and plain comments so far as answered, the first time a check sees the PR. Threads are not
    /// marked: an open thread is real work.
    mutating func seed(_ pr: OpenPR) {
        guard !seeded else { return }
        let known = Set(answered)
        answered += (pr.reviews.map(\.id) + pr.comments.map(\.id)).filter { !known.contains($0) }
        seeded = true
    }

    /// The round's state merged with the state on disk, which the user or `act` may have changed while the round ran.
    /// A call the user removed during the round stays removed. Answered ids and resolved threads union, `handled` keeps
    /// the disk's value for each key, `off` comes from disk, and a held fix comes from disk unless the round set one.
    func merged(disk d: TendPR, startCalls: Set<String>) -> TendPR {
        var out = self
        let removed = startCalls.subtracting(d.calls.map(\.id))
        let answeredNow = Set(d.answered)
        out.calls = calls.filter { !removed.contains($0.id) && !answeredNow.contains($0.id) }
        out.answered += d.answered.filter { !answered.contains($0) }
        out.resolvedByUs += d.resolvedByUs.filter { !resolvedByUs.contains($0) }
        out.handled.merge(d.handled) { _, disk in disk }
        out.off = d.off
        if out.held == nil { out.held = d.held }
        return out
    }
}

/// One line of `stateDir/tend/tower.jsonl`: something tend did or needs, for the tower view. `amber` marks a line that
/// needs the user.
struct TowerLine: Codable, Equatable {
    var at: Date
    var slug: String
    var n: Int
    var text: String
    var detail: String?
    var amber: Bool
}

/// Tend's files under `stateDir/tend`. State files and the approach snapshot are written atomically; the tower log
/// gets one line per append.
struct TendStore {
    let paths: Paths

    var dir: String { paths.stateDir + "/tend" }

    /// Files in `dir` that are not one PR's state.
    static let sharedFiles: Set<String> = ["approach.json", "landed.json", "briefing.json", "lessons.json",
                                           "council.json", "queue.json"]

    private static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func stem(_ slug: String, _ n: Int) -> String {
        slug.replacingOccurrences(of: "/", with: "-") + "-\(n)"
    }

    func file(_ slug: String, _ n: Int) -> String { dir + "/" + stem(slug, n) + ".json" }

    /// The lock a PR's state is read and changed under, so two writers never interleave.
    func lockPath(_ slug: String, _ n: Int) -> String { dir + "/" + stem(slug, n) + ".lock" }

    /// The worktree a PR's fixes are made in.
    func wtDir(_ slug: String, _ n: Int) -> String { dir + "/wt/" + stem(slug, n) }

    /// The worktree a revert PR's commit is made in. Removed once the PR is open.
    func revertDir(_ slug: String, _ n: Int) -> String { dir + "/wt/revert-" + stem(slug, n) }

    func load(_ slug: String, _ n: Int) -> TendPR? {
        guard let data = FileManager.default.contents(atPath: file(slug, n)) else { return nil }
        return try? RunStore.decoder().decode(TendPR.self, from: data)
    }

    func save(_ state: TendPR) throws {
        try write(RunStore.encoder().encode(state), to: file(state.slug, state.n))
    }

    func remove(_ slug: String, _ n: Int) {
        try? FileManager.default.removeItem(atPath: file(slug, n))
    }

    /// Every readable PR state file.
    func all() -> [TendPR] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasSuffix(".json") && !TendStore.sharedFiles.contains($0) }.compactMap { name in
            FileManager.default.contents(atPath: dir + "/" + name).flatMap { try? RunStore.decoder().decode(TendPR.self, from: $0) }
        }
    }

    func loadApproach() -> ApproachSnapshot? {
        guard let data = FileManager.default.contents(atPath: dir + "/approach.json") else { return nil }
        return try? RunStore.decoder().decode(ApproachSnapshot.self, from: data)
    }

    func saveApproach(_ snapshot: ApproachSnapshot) throws {
        try write(RunStore.encoder().encode(snapshot), to: dir + "/approach.json")
    }

    /// Sets one PR's `off` in the approach snapshot now, so the switch moves before the next check.
    func patchPlaneOff(_ slug: String, _ n: Int, _ off: Bool) {
        guard var snapshot = loadApproach(), let i = snapshot.planes.firstIndex(where: { $0.slug == slug && $0.n == n })
        else { return }
        snapshot.planes[i].off = off
        try? saveApproach(snapshot)
    }

    func appendTower(_ line: TowerLine) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var data = try TendStore.lineEncoder.encode(line)
        data.append(0x0A)
        let path = dir + "/tower.jsonl"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// The newest `limit` tower lines, newest first. Lines that do not read are skipped.
    func tower(limit: Int) -> [TowerLine] {
        guard let text = try? String(contentsOfFile: dir + "/tower.jsonl", encoding: .utf8) else { return [] }
        let decoder = RunStore.decoder()
        return text.split(separator: "\n").suffix(limit).reversed().compactMap { line in
            try? decoder.decode(TowerLine.self, from: Data(line.utf8))
        }
    }

    func loadBriefing() -> Briefing? {
        guard let data = FileManager.default.contents(atPath: dir + "/briefing.json") else { return nil }
        return try? RunStore.decoder().decode(Briefing.self, from: data)
    }

    func saveBriefing(_ briefing: Briefing) throws {
        try write(RunStore.encoder().encode(briefing), to: dir + "/briefing.json")
    }

    func loadLessonsRun() -> LessonsRun? {
        guard let data = FileManager.default.contents(atPath: dir + "/lessons.json") else { return nil }
        return try? RunStore.decoder().decode(LessonsRun.self, from: data)
    }

    func saveLessonsRun(_ run: LessonsRun) throws {
        try write(RunStore.encoder().encode(run), to: dir + "/lessons.json")
    }

    func write(_ data: Data, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// `tend/lessons.json`: when the weekly lesson consolidation last ran.
struct LessonsRun: Codable, Equatable {
    var lastRun: Date?
}

/// What the checks looked like, for telling a new failure from one a round already tried. The order of checks does
/// not matter. Format: the head, then `|`, then `name=conclusion` (or status while running) joined by `,`.
enum Fingerprint {
    static func ci(_ pr: OpenPR) -> String {
        pr.head + "|" + pr.checks.map { "\($0.name)=\($0.conclusion ?? $0.status)" }.sorted().joined(separator: ",")
    }

    /// The checks, then the open threads with their last comment, the reviews with their state, the plain comments
    /// not by `me`, the base branch, the merge state and the review decision. Each part is sorted and joined by `|`. A
    /// new comment, review, base or merge state changes it; the order of listing does not.
    static func full(_ pr: OpenPR, me: String) -> String {
        let threads = pr.threads.filter { !$0.isResolved }
            .map { "\($0.id):\($0.comments.last?.id ?? "")" }.sorted().joined(separator: ",")
        let reviews = pr.reviews.map { "\($0.id):\($0.state)" }.sorted().joined(separator: ",")
        let comments = pr.comments.filter { $0.author.caseInsensitiveCompare(me) != .orderedSame }
            .map(\.id).sorted().joined(separator: ",")
        return [ci(pr), threads, reviews, comments, pr.base, pr.mergeStateStatus ?? "", pr.reviewDecision ?? ""]
            .joined(separator: "|")
    }
}

/// How many rounds a day and tries on one head tend may use.
enum TendLimits {
    /// Starts the day's count when `today` is not the day the count was kept for.
    static func rollDay(_ s: inout TendPR, _ today: Date, calendar: Calendar = .current) {
        if let day = s.roundsDate, calendar.isDate(day, inSameDayAs: today) { return }
        s.roundsToday = 0
        s.roundsDate = today
    }

    /// Why a round may not start on `head`, or nil. Call `rollDay` first.
    static func blocked(_ s: TendPR, head: String, _ cfg: TendConfig) -> String? {
        if s.roundsToday >= cfg.roundsPerDay { return "\(cfg.roundsPerDay) rounds a day reached" }
        if (s.triesByHead[head] ?? 0) >= cfg.triesPerHead { return "\(cfg.triesPerHead) tries on this head used" }
        return nil
    }
}

/// What a PR needs from tend on this sweep.
enum TendDecision: Equatable {
    case skip(String)
    case idle
    case round(WorkClass)

    /// A round when CI failed, a thread, review or comment asks for an answer, or the PR conflicts with its base, and the
    /// PR's full fingerprint is new. Pending CI waits. The round is urgent only when the PR is approved and CI failed or
    /// it conflicts.
    static func decide(_ pr: OpenPR, state: TendPR, me: String) -> TendDecision {
        if pr.isFork { return .skip("fork") }
        if !Approach.tendable(pr, state) { return .skip("hands off") }
        if state.held != nil { return .idle }
        guard pr.ciStatus != .pending else { return .idle }
        let conflicts = pr.mergeStateStatus == "DIRTY"
        let asks = pendingAsks(pr, state: state, me: me)
        guard pr.ciStatus == .failed || conflicts || !asks.isEmpty else { return .idle }
        guard state.fingerprint != Fingerprint.full(pr, me: me) else { return .idle }
        return .round(pr.approved && (pr.ciStatus == .failed || conflicts) ? .urgent : .normal)
    }

    /// What a round answers: the threads, reviews and comments that wait on someone, then the self-review findings not
    /// yet answered.
    static func pendingAsks(_ pr: OpenPR, state: TendPR, me: String) -> [Ask] {
        let open = Threads.actionable(pr, me: me, answered: Set(state.answered), handled: state.handled)
        let own = state.selfReview.map { Threads.selfAsks($0, answered: Set(state.answered)) } ?? []
        return open + own
    }

    /// True when the PR has a new head since its stuck mark was set, so the mark goes.
    static func clearsStuck(_ pr: OpenPR, state: TendPR) -> Bool {
        guard let fingerprint = state.fingerprint else { return false }
        return String(fingerprint.prefix { $0 != "|" }) != pr.head
    }
}

/// Failure evidence for a fix round, read from the CI log.
enum CIEvidence {
    /// The run and job ids in a check's URL (`/actions/runs/<r>/job/<j>`). Nil when the URL names no run.
    static func ids(_ url: String?) -> (run: Int, job: Int?)? {
        guard let url, let at = url.range(of: "/actions/runs/") else { return nil }
        let rest = url[at.upperBound...]
        guard let run = Int(rest.prefix(while: { $0.isNumber })) else { return nil }
        var job: Int?
        if let j = rest.range(of: "/job/") {
            job = Int(rest[j.upperBound...].prefix(while: { $0.isNumber }))
        }
        return (run, job)
    }

    /// The lines around each `##[error]`, merged where they touch, capped at `cap` lines. A log with no error gives its
    /// last 300 lines.
    static func windows(_ log: String, before: Int = 60, after: Int = 20, cap: Int = 400) -> [String] {
        // Job logs carry ANSI colour codes; the session reads plain text.
        let plain = log.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        let lines = plain.components(separatedBy: "\n")
        let errors = lines.indices.filter { lines[$0].contains("##[error]") }
        guard !errors.isEmpty else { return Array(lines.suffix(300)) }
        var merged: [ClosedRange<Int>] = []
        for e in errors {
            let range = max(0, e - before)...min(lines.count - 1, e + after)
            if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return Array(merged.flatMap { lines[$0] }.prefix(cap))
    }
}
