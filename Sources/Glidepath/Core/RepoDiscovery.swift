import Foundation

/// A repo the onboarding list offers, from the user's account or one of its orgs.
struct DiscoveredRepo: Equatable {
    let slug: String
    let language: String?
    let pushedAt: Date?
    /// Open PRs in the repo, from one `gh search prs` per owner. nil when that owner's search failed or has not run yet.
    var openPRs: Int?
}

/// Lists the repos for the onboarding step with `gh`: the user's own and each org's, newest push first, up to `cap`.
/// Two phases, each with its owners' calls run in parallel: `loadRepos` lists the repos, then `loadOpenCounts`
/// adds the open PR counts (`gh repo list` has none, so one `gh search prs` per owner).
enum RepoDiscovery {
    static let cap = 300
    /// Per gh call. An owner that exceeds it is skipped.
    static let timeout: TimeInterval = 30

    struct Listing: Sendable {
        let repos: [DiscoveredRepo]
        /// The user's login first, then the orgs. Phase 2 searches these.
        let owners: [String]
    }

    /// Blocking: call it off the main thread. Throws when the user's own list cannot be read.
    static func loadRepos(env: [String: String]) throws -> Listing {
        let me = try gh(["api", "user", "--jq", ".login"], env: env).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty else { throw ConfigError(message: "gh did not return your GitHub login") }
        // An org the user cannot list is skipped rather than failing the whole step.
        let orgs = (try? gh(["api", "user/orgs", "--paginate", "--jq", ".[].login"], env: env)) ?? ""
        let owners = [me] + orgs.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let lists = parallel(owners.map { ["repo", "list", $0, "--limit", "\(cap)", "--no-archived",
                                           "--json", "nameWithOwner,primaryLanguage,pushedAt"] }, env: env)
        // The user's own list is required; an org that fails is skipped.
        guard (lists.first ?? nil) != nil else { throw ConfigError(message: "gh repo list \(me) failed") }
        let repos = merge(lists.compactMap { $0.map(parseRepos) })
        return Listing(repos: repos, owners: owners)
    }

    /// Blocking: call it off the main thread. Returns the open PR count per slug, and the owners whose search succeeded.
    static func loadOpenCounts(owners: [String], env: [String: String]) -> (counts: [String: Int], searched: Set<String>) {
        let results = parallel(owners.map { ["search", "prs", "--owner", $0, "--state", "open",
                                             "--limit", "1000", "--json", "repository"] }, env: env)
        var counts: [String: Int] = [:]
        var searched = Set<String>()
        for (owner, data) in zip(owners, results) {
            guard let data else { continue }
            searched.insert(owner)
            for (slug, n) in parseOpenCounts(data) { counts[slug, default: 0] += n }
        }
        return (counts, searched)
    }

    /// Sets each repo's open PR count from the search results. Repos whose owner was not searched keep nil.
    static func applyOpenCounts(_ counts: [String: Int], searched: Set<String>, to repos: [DiscoveredRepo]) -> [DiscoveredRepo] {
        repos.map { repo in
            var repo = repo
            let owner = String(repo.slug.split(separator: "/").first ?? "")
            if searched.contains(owner) { repo.openPRs = counts[repo.slug] ?? 0 }
            return repo
        }
    }

    /// Merges the owners' lists: the first copy of each slug wins, newest push first, up to `cap`.
    static func merge(_ lists: [[DiscoveredRepo]], cap: Int = cap) -> [DiscoveredRepo] {
        var seen = Set<String>()
        let unique = lists.flatMap { $0 }.filter { seen.insert($0.slug).inserted }
        let sorted = unique.sorted {
            let a = $0.pushedAt ?? .distantPast, b = $1.pushedAt ?? .distantPast
            return a != b ? a > b : $0.slug < $1.slug
        }
        return Array(sorted.prefix(cap))
    }

    /// Repos from `gh repo list --json nameWithOwner,primaryLanguage,pushedAt`. Entries without a valid slug are dropped.
    static func parseRepos(_ data: Data) -> [DiscoveredRepo] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let formatter = ISO8601DateFormatter()
        return items.compactMap { item in
            guard let slug = item["nameWithOwner"] as? String, RepoConfig.isValidSlug(slug) else { return nil }
            let language = (item["primaryLanguage"] as? [String: Any])?["name"] as? String
            let pushed = (item["pushedAt"] as? String).flatMap { formatter.date(from: $0) }
            return DiscoveredRepo(slug: slug, language: language, pushedAt: pushed, openPRs: nil)
        }
    }

    /// Open PR counts per slug from `gh search prs --json repository`, one entry per PR.
    static func parseOpenCounts(_ data: Data) -> [String: Int] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var counts: [String: Int] = [:]
        for item in items {
            let repository = item["repository"]
            let slug = (repository as? [String: Any])?["nameWithOwner"] as? String ?? repository as? String
            if let slug { counts[slug, default: 0] += 1 }
        }
        return counts
    }

    /// Runs one gh call per argument list, all at once. Each slot is that call's stdout, or nil when it failed or timed out.
    private static func parallel(_ calls: [[String]], env: [String: String]) -> [Data?] {
        final class Slots: @unchecked Sendable {
            var values: [Data?]
            let lock = NSLock()
            init(count: Int) { values = Array(repeating: nil, count: count) }
        }
        let slots = Slots(count: calls.count)
        DispatchQueue.concurrentPerform(iterations: calls.count) { index in
            let data = try? Data(gh(calls[index], env: env).utf8)
            slots.lock.lock()
            slots.values[index] = data
            slots.lock.unlock()
        }
        return slots.values
    }

    private static func gh(_ args: [String], env: [String: String]) throws -> String {
        let r = Shell.run("gh", args, env: env, timeout: timeout)
        guard r.ok else {
            let last = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
            throw ConfigError(message: "gh \(args.prefix(2).joined(separator: " ")) failed\(last.isEmpty ? "" : ": \(last)")")
        }
        return r.stdout
    }
}
