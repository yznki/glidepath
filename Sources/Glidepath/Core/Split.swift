import Foundation

/// One part of a split: what it is, why it stands alone, and the changed files it takes. `dependsOn` is the 1-based
/// index of the earlier part it builds on, or nil.
struct SplitPart: Codable, Equatable {
    var title: String
    var why = ""
    var files: [String] = []
    var dependsOn: Int? = nil

    enum CodingKeys: String, CodingKey {
        case title, why, files
        case dependsOn = "depends_on"
    }
}

extension SplitPart {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        dependsOn = try c.decodeIfPresent(Int.self, forKey: .dependsOn)
    }
}

/// A split proposed for one of the user's PRs, in `tend/split/<owner>-<name>-<n>.json`. `head` is the PR head it was
/// planned for. `status` is "planning", "proposed", "building", "built", "failed" or "kept".
struct SplitPlan: Codable, Equatable {
    var slug: String
    var n: Int
    var head: String
    var branch: String
    var base: String
    var parts: [SplitPart]
    var status: String
    var failed: String? = nil
    /// The PR number of each part once it is open, in part order.
    var prs: [Int] = []
    /// One line per check command the build ran, e.g. "part 1: npm test ok".
    var checks: [String] = []
    var at: Date
}

extension SplitPlan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        n = try c.decode(Int.self, forKey: .n)
        head = try c.decode(String.self, forKey: .head)
        branch = try c.decode(String.self, forKey: .branch)
        base = try c.decode(String.self, forKey: .base)
        parts = try c.decode([SplitPart].self, forKey: .parts)
        status = try c.decode(String.self, forKey: .status)
        failed = try c.decodeIfPresent(String.self, forKey: .failed)
        prs = try c.decodeIfPresent([Int].self, forKey: .prs) ?? []
        checks = try c.decodeIfPresent([String].self, forKey: .checks) ?? []
        at = try c.decode(Date.self, forKey: .at)
    }
}

/// Split plans: validation, the branch chain, the stack table, reading a plan session's answer, and when a PR is due one.
enum Split {
    static let partCounts = 2...6
    static let titleLimit = 120
    static let whyLimit = 500
    /// A plan still planning or building this long after `at` was interrupted.
    static let staleAfter: TimeInterval = 2 * 3600

    /// The first problem with the parts, or nil. Every part names only changed files, and each changed file is in
    /// exactly one part. Each part has a title and files; `dependsOn` is nil or an earlier part. A title is one line.
    static func validate(_ parts: [SplitPart], changed: [String]) -> String? {
        guard partCounts.contains(parts.count) else { return "A split has 2 to 6 parts, not \(parts.count)" }
        for (i, part) in parts.enumerated() {
            let k = i + 1
            if part.title.trimmingCharacters(in: .whitespaces).isEmpty { return "Part \(k) has no title" }
            if part.title.count > titleLimit || part.title.rangeOfCharacter(from: .newlines) != nil {
                return "Part \(k)'s title is over \(titleLimit) characters or has a line break"
            }
            if part.why.count > whyLimit { return "Part \(k)'s why is over \(whyLimit) characters" }
            if part.files.isEmpty { return "Part \(k) has no files" }
            if let dep = part.dependsOn, !(1..<k).contains(dep) {
                return "Part \(k) depends on part \(dep), which is not an earlier part"
            }
        }
        let known = Set(changed)
        var seen = Set<String>()
        for file in parts.flatMap(\.files) {
            if !known.contains(file) { return "\(file) is not changed in this PR" }
            if !seen.insert(file).inserted { return "\(file) is in more than one part" }
        }
        if let missing = changed.first(where: { !seen.contains($0) }) { return "\(missing) is in no part" }
        return nil
    }

    /// Each part's branch and base, in order: part k is `<branch>-part-k`, based on part k−1's branch. Part 1 is based on
    /// `base`, the PR's own base.
    static func branches(branch: String, base: String, count: Int) -> [(branch: String, base: String)] {
        (0..<count).map { i -> (branch: String, base: String) in
            (branch: "\(branch)-part-\(i + 1)", base: i == 0 ? base : "\(branch)-part-\(i)")
        }
    }

    /// The stack as a markdown list, one line per part: "1. #10 Title". The part `current` (1-based) is marked
    /// "← this PR". A part without a PR yet shows "(new)".
    static func stackTable(_ parts: [SplitPart], prs: [Int], current: Int) -> String {
        parts.enumerated().map { i, part in
            let ref = i < prs.count ? "#\(prs[i])" : "(new)"
            return "\(i + 1). \(ref) \(part.title)" + (i + 1 == current ? " ← this PR" : "")
        }.joined(separator: "\n")
    }

    /// The first title or why that may not go on GitHub, by the reply guard's rules: no mention, link or markup. Nil when
    /// every part's text may go.
    static func publicTextRefusal(_ parts: [SplitPart], slug: String, n: Int) -> String? {
        for (i, part) in parts.enumerated() {
            for text in [part.title, part.why] where ReplyGuard.check(text, author: "", slug: slug, n: n) != nil {
                return "Part \(i + 1) has a mention, a link or markup, which a PR may not carry"
            }
        }
        return nil
    }

    /// Whether a planning or building plan is stale: its `at` is more than `staleAfter` old, so it was interrupted.
    static func isStale(_ plan: SplitPlan, now: Date) -> Bool {
        ["planning", "building"].contains(plan.status) && now.timeIntervalSince(plan.at) > staleAfter
    }

    /// The plan as it stands now: a stale plan reads as failed, "Interrupted".
    static func effective(_ plan: SplitPlan, now: Date) -> SplitPlan {
        guard isStale(plan, now: now) else { return plan }
        var out = plan
        out.status = "failed"
        out.failed = "Interrupted"
        return out
    }

    /// Whether a branch is one a split built, `<branch>-part-<k>`. Those are never split again.
    static func isPartBranch(_ branch: String) -> Bool {
        branch.range(of: #"-part-\d+$"#, options: .regularExpression) != nil
    }

    /// The parts in a plan session's answer: the last line that reads as `{"parts": [...]}` or a bare array, from its
    /// first brace or bracket. Nil when none does.
    static func parse(_ text: String) -> [SplitPart]? {
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { continue }
            let json = Data(trimmed[start...].utf8)
            if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: json) { return wrapped.parts }
            if let parts = try? JSONDecoder().decode([SplitPart].self, from: json) { return parts }
        }
        return nil
    }

    /// A PR a split plan is due for: not a draft, a fork, hands-off or a part branch, over `overLines` changed lines, and
    /// no plan for it at all, whatever its head or status. Automatic planning happens once per PR; the user can replan
    /// with Split. The caller passes only PRs tending is on for.
    static func due(_ pr: OpenPR, plan: SplitPlan?, overLines: Int) -> Bool {
        !pr.isDraft && !pr.isFork && Approach.tendable(pr, nil) && !isPartBranch(pr.branch)
            && pr.additions + pr.deletions > overLines && plan == nil
    }

    private struct Wrapped: Decodable {
        var parts: [SplitPart]
    }
}
