import Foundation

/// A repo the onboarding list offers, from the user's account or one of its orgs.
struct DiscoveredRepo: Equatable {
    let slug: String
    let language: String?
    let pushedAt: Date?
    /// Open PRs in the repo, from one `gh search prs` per owner. nil when that owner's search failed.
    var openPRs: Int?
}

/// Lists the repos for the onboarding step with `gh`: the user's own and each org's, newest push first, up to `cap`.
/// `gh search prs` supplies the open PR counts, one search per owner, since `gh repo list` has no count.
enum RepoDiscovery {
    static let cap = 300

    /// Blocking: call it off the main thread. Throws when the user's own list cannot be read.
    static func load(env: [String: String]) throws -> [DiscoveredRepo] {
        let me = try gh(["api", "user", "--jq", ".login"], env: env).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty else { throw ConfigError(message: "gh did not return your GitHub login") }
        // An org the user cannot list is skipped rather than failing the whole step.
        let orgs = (try? gh(["api", "user/orgs", "--paginate", "--jq", ".[].login"], env: env)) ?? ""
        let owners = [me] + orgs.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        var repos: [DiscoveredRepo] = []
        var seen = Set<String>()
        for owner in owners {
            guard let data = try? ghData(["repo", "list", owner, "--limit", "\(cap)", "--no-archived",
                                          "--json", "nameWithOwner,primaryLanguage,pushedAt"], env: env) else { continue }
            for repo in parseRepos(data) where seen.insert(repo.slug).inserted {
                repos.append(repo)
            }
        }
        repos.sort { ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast) }
        repos = Array(repos.prefix(cap))

        var counts: [String: Int] = [:]
        var searched = Set<String>()
        for owner in owners {
            guard let data = try? ghData(["search", "prs", "--owner", owner, "--state", "open",
                                          "--limit", "1000", "--json", "repository"], env: env) else { continue }
            searched.insert(owner)
            for (slug, n) in parseOpenCounts(data) { counts[slug, default: 0] += n }
        }
        for index in repos.indices {
            let owner = String(repos[index].slug.split(separator: "/").first ?? "")
            if searched.contains(owner) { repos[index].openPRs = counts[repos[index].slug] ?? 0 }
        }
        return repos
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

    private static func ghData(_ args: [String], env: [String: String]) throws -> Data {
        Data(try gh(args, env: env).utf8)
    }

    private static func gh(_ args: [String], env: [String: String]) throws -> String {
        let r = Shell.run("gh", args, env: env, timeout: 120)
        guard r.ok else {
            let last = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
            throw ConfigError(message: "gh \(args.prefix(2).joined(separator: " ")) failed\(last.isEmpty ? "" : ": \(last)")")
        }
        return r.stdout
    }
}
