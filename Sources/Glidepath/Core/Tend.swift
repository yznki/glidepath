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

/// A reply tend has drafted or agreed to post. `askId` is the ask it answers; `resolve` closes its thread after.
struct PendingReply: Codable, Equatable {
    var askId: String
    var kind: String
    var body: String
    var resolve: Bool
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
    }

    private enum CodingKeys: String, CodingKey {
        case slug, n, fingerprint, roundsToday, roundsDate, triesByHead, rerunsByHead, held, stuck, off
        case pendingRan, pendingRanHead, lastRound, answered, resolvedByUs, calls, rereq
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

    private static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func stem(_ slug: String, _ n: Int) -> String {
        slug.replacingOccurrences(of: "/", with: "-") + "-\(n)"
    }

    func file(_ slug: String, _ n: Int) -> String { dir + "/" + stem(slug, n) + ".json" }

    /// The worktree a PR's fixes are made in.
    func wtDir(_ slug: String, _ n: Int) -> String { dir + "/wt/" + stem(slug, n) }

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
        return names.filter { $0.hasSuffix(".json") && $0 != "approach.json" }.compactMap { name in
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

    private func write(_ data: Data, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// What the checks looked like, for telling a new failure from one a round already tried. The order of checks does
/// not matter. Format: the head, then `|`, then `name=conclusion` (or status while running) joined by `,`.
enum Fingerprint {
    static func ci(_ pr: OpenPR) -> String {
        pr.head + "|" + pr.checks.map { "\($0.name)=\($0.conclusion ?? $0.status)" }.sorted().joined(separator: ",")
    }

    /// The checks, then the open threads with their last comment, the reviews with their state, and the plain comments
    /// not by `me`, each part sorted and joined by `|`. A new comment or review changes it; the order of listing does not.
    static func full(_ pr: OpenPR, me: String) -> String {
        let threads = pr.threads.filter { !$0.isResolved }
            .map { "\($0.id):\($0.comments.last?.id ?? "")" }.sorted().joined(separator: ",")
        let reviews = pr.reviews.map { "\($0.id):\($0.state)" }.sorted().joined(separator: ",")
        let comments = pr.comments.filter { $0.author.caseInsensitiveCompare(me) != .orderedSame }
            .map(\.id).sorted().joined(separator: ",")
        return [ci(pr), threads, reviews, comments].joined(separator: "|")
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

    /// A round when CI failed or a thread, review or comment asks for an answer, and the PR's full fingerprint is new.
    /// Pending CI waits. The round is urgent only when the PR is approved and CI failed.
    static func decide(_ pr: OpenPR, state: TendPR, me: String) -> TendDecision {
        if pr.isFork { return .skip("fork") }
        if !Approach.tendable(pr, state) { return .skip("hands off") }
        if state.held != nil { return .idle }
        guard pr.ciStatus != .pending else { return .idle }
        let asks = Threads.actionable(pr, me: me, answered: Set(state.answered))
        guard pr.ciStatus == .failed || !asks.isEmpty else { return .idle }
        guard state.fingerprint != Fingerprint.full(pr, me: me) else { return .idle }
        return .round(pr.approved && pr.ciStatus == .failed ? .urgent : .normal)
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
