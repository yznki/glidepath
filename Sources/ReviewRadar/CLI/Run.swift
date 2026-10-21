import Foundation

/// Clone management shared by `init` and `run`. Clones are detached at the default branch and are
/// never used for work; a dirty clone stops the run instead of being reset.
enum RepoClone {
    /// Upper bound for clone and fetch. A stuck network should not hold the run lock for hours.
    static let slowTimeout: TimeInterval = 30 * 60

    static func sync(_ repo: RepoConfig, env: [String: String]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: repo.clone + "/.git") {
            var createdHere = false
            if fm.fileExists(atPath: repo.clone) {
                let contents = (try? fm.contentsOfDirectory(atPath: repo.clone)) ?? []
                guard contents.isEmpty else {
                    throw RunError("\(repo.clone) exists and is not a git checkout; move it aside or change clone")
                }
            } else {
                createdHere = true
            }
            let r = gh(["repo", "clone", repo.slug, repo.clone, "--", "--filter=blob:none", "--quiet"], env, slowTimeout)
            guard r.ok else {
                // Remove what this call created, so the next run starts clean instead of finding a half clone.
                if createdHere { try? fm.removeItem(atPath: repo.clone) }
                throw RunError("clone failed: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        try excludeGitNexusIndex(repo.clone)

        let status = git(["-C", repo.clone, "status", "--porcelain"], env, 120)
        guard status.ok else {
            throw RunError("clone is broken, delete \(repo.clone) and run again (git status failed)")
        }
        guard status.stdout.isEmpty else {
            throw RunError("clone at \(repo.clone) has local changes; refusing to run")
        }
        let branch = gh(["repo", "view", repo.slug, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"], env, 120)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { throw RunError("could not read the default branch") }
        guard git(["-C", repo.clone, "fetch", "--quiet", "--prune", "origin"], env, slowTimeout).ok else {
            throw RunError("git fetch failed")
        }
        guard git(["-C", repo.clone, "checkout", "--quiet", "--detach", "origin/\(branch)"], env, 120).ok else {
            throw RunError("could not check out origin/\(branch)")
        }
    }

    /// GitNexus writes its index into the checkout. Excluding it keeps `git status` clean, so the
    /// clean-clone check still passes.
    static func excludeGitNexusIndex(_ clone: String) throws {
        let path = clone + "/.git/info/exclude"
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard !existing.split(separator: "\n").contains(".gitnexus/") else { return }
        let prefix = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try (existing + prefix + ".gitnexus/\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func gh(_ args: [String], _ env: [String: String], _ timeout: TimeInterval) -> ShellResult {
        Shell.run("gh", args, env: env, timeout: timeout)
    }

    private static func git(_ args: [String], _ env: [String: String], _ timeout: TimeInterval) -> ShellResult {
        Shell.run("git", args, env: env, timeout: timeout)
    }
}

struct RunError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `review-radar run [--dry-run] [--repo slug] [--scheduled]`.
enum RunCommand {
    static func main(_ args: [String]) -> Int32 {
        let a = Args(args, valued: ["--repo"])
        let paths = Paths()
        if a.has("--scheduled") && Pause.isPaused(paths) {
            print("paused; scheduled run skipped")
            return 0
        }
        let config: Config
        do {
            config = try Config.load(paths)
        } catch {
            eprint("\(error)")
            return 1
        }
        var repos = config.repos
        if let slug = a.value("--repo") {
            repos = repos.filter { $0.slug == slug }
            guard !repos.isEmpty else {
                eprint("repo \(slug) is not in the config")
                return 1
            }
        }
        guard !repos.isEmpty else {
            eprint("no repos configured; run review-radar init")
            return 1
        }
        let lock: RunLock
        do {
            guard let held = try RunLock.acquire(paths.lockFile) else {
                eprint("another run is in progress")
                return 1
            }
            lock = held
        } catch {
            eprint("\(error)")
            return 1
        }
        let runner = Runner(paths: paths, config: config, dryRun: a.has("--dry-run"))
        return withExtendedLifetime(lock) { runner.execute(repos: repos) }
    }
}

/// One run: for each repo, sync the clone, filter open PRs, then hand the kept ones to Claude.
/// Every state change goes through `update`, which reloads the run first, because the review skill
/// writes the same file from its own process.
final class Runner {
    let paths: Paths
    let config: Config
    let dryRun: Bool
    let store: RunStore
    let env: [String: String]
    private(set) var id = ""
    private var collaboratorCache: [String: Bool] = [:]
    private var me = ""

    init(paths: Paths, config: Config, dryRun: Bool) {
        self.paths = paths
        self.config = config
        self.dryRun = dryRun
        self.store = RunStore(paths: paths)
        self.env = Runner.environment(paths)
    }

    /// The launchd job's PATH when it is installed, so `run now` from the app finds claude and gh.
    static func environment(_ paths: Paths) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let data = FileManager.default.contents(atPath: paths.plistFile),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let vars = dict["EnvironmentVariables"] as? [String: String],
           let path = vars["PATH"] {
            env["PATH"] = path
        }
        return env
    }

    func execute(repos: [RepoConfig]) -> Int32 {
        let now = Date()
        id = Runner.makeID(now)
        do {
            try store.save(RunState.new(id: id, now: now))
            if !dryRun { try store.makeCurrent(id) }
        } catch {
            eprint("cannot create run \(id): \(error)")
            return 1
        }
        print("run \(id)\(dryRun ? " (dry run)" : "")")

        var failed = false
        var totalTokens = 0
        do {
            me = try login()
            for repo in repos {
                do {
                    totalTokens += try process(repo)
                } catch {
                    failed = true
                    print("\(repo.slug): \(error)")
                    try? update { $0.setRepoError(repo.slug, "\(error)") }
                }
            }
        } catch {
            failed = true
            print("\(error)")
            try? update { $0.error = "\(error)" }
        }

        try? update { run in
            run.finish(at: Date(), error: run.error)
            run.tokens = totalTokens
        }
        printSummary()
        return failed ? 1 : 0
    }

    // MARK: Per repo

    /// Returns the tokens this repo's session used.
    private func process(_ repo: RepoConfig) throws -> Int {
        try prepareClone(repo)
        let prs = try listPRs(repo)

        var kept: [PRInfo] = []
        var skipped: [(PRInfo, String)] = []
        for pr in prs {
            let decision = PRFilter.evaluate(
                pr, me: me, authors: repo.authors, limits: config.limits,
                isCollaborator: { self.isCollaborator(repo, login: pr.author) },
                reviewedHeads: { self.reviewedHeads(repo, pr.n) })
            switch decision {
            case .keep where kept.count < config.limits.maxPRsPerRun:
                kept.append(pr)
            case .keep:
                skipped.append((pr, "over max_prs_per_run"))
            case .skip(let reason):
                skipped.append((pr, reason))
            }
        }

        try update { run in
            run.ensureRepo(repo.slug)
            for (pr, reason) in skipped {
                try run.setPR(repo: repo.slug, n: pr.n, stage: nil, author: pr.author, title: pr.title,
                              verdict: .skipped, reason: reason)
            }
            for pr in kept {
                try run.setPR(repo: repo.slug, n: pr.n, stage: nil, author: pr.author, title: pr.title,
                              verdict: nil, reason: nil)
            }
        }
        guard !kept.isEmpty else { return 0 }
        return try invokeReview(repo, kept: kept)
    }

    private func invokeReview(_ repo: RepoConfig, kept: [PRInfo]) throws -> Int {
        let numbers = kept.map(\.n)
        let session = UUID().uuidString.lowercased()
        let scratch = paths.scratchDir + "/" + id + "/" + repo.owner + "-" + repo.name
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        let gitnexus = gitnexusEnabled(repo)

        let prompt = [
            "/review-radar", repo.slug, numbers.map(String.init).joined(separator: ","),
            "run=\(id)", "scratch=\(scratch)", "posting=\(repo.posting.rawValue)",
            "gitnexus=\(gitnexus ? "on" : "off")", "rules=\(repo.rules ?? "none")",
            "rules_mode=\(repo.rulesMode.rawValue)", "split_over=\(config.limits.splitOverLines)",
            "dry_run=\(dryRun)",
        ].joined(separator: " ")

        let args = [
            "-p", prompt,
            "--model", "opus",
            "--permission-mode", "dontAsk",
            "--session-id", session,
            "--add-dir", scratch,
            "--allowedTools", allowlist(repo, scratch: scratch, gitnexus: gitnexus).joined(separator: ","),
        ]
        print("\(repo.slug): reviewing \(numbers.map { "#\($0)" }.joined(separator: " "))")
        let result = Shell.run("claude", args, cwd: repo.clone, env: env, timeout: 3600)
        let logPath = scratch + "/claude.log"
        try? (result.stdout + result.stderr).write(toFile: logPath, atomically: true, encoding: .utf8)
        if dryRun { print(result.stdout) }

        let usage = Transcript.usage(paths: paths, cwd: repo.clone, sessionId: session, keptPRs: Set(numbers))
        try update { run in
            for (n, tokens) in usage.byPR {
                run.addTokens(repo: repo.slug, n: n, tokens: tokens)
            }
            if !result.ok {
                run.setRepoError(repo.slug, "claude exited \(result.status); see \(logPath)")
            }
        }
        return usage.total
    }

    /// Only these tools run without a prompt. Posting goes through `gh api`, which is left out of
    /// dry runs because the allow rule cannot tell a POST from a GET.
    func allowlist(_ repo: RepoConfig, scratch: String, gitnexus: Bool) -> [String] {
        var list = [
            "Read", "Grep", "Glob", "Agent",
            "Bash(git fetch:*)", "Bash(git diff:*)", "Bash(git show:*)", "Bash(git log:*)",
            "Bash(gh pr view:*)", "Bash(gh pr diff:*)", "Bash(gh pr list:*)",
            "Bash(review-radar state:*)",
            "Edit(\(absoluteRule(scratch))/**)",
        ]
        if let rules = repo.rules { list.append("Read(\(absoluteRule(rules)))") }
        if !dryRun { list.append("Bash(gh api repos/*/pulls/*/reviews:*)") }
        if gitnexus { list.append("mcp__gitnexus__*") }
        return list
    }

    /// Permission rules write absolute paths as `//path`; a single leading slash means project-relative.
    private func absoluteRule(_ path: String) -> String {
        path.hasPrefix("/") ? "/" + path : path
    }

    private func gitnexusEnabled(_ repo: RepoConfig) -> Bool {
        switch repo.gitnexus {
        case .on: return true
        case .off: return false
        case .auto: return Shell.find("gitnexus", path: env["PATH"]) != nil
        }
    }

    // MARK: GitHub and git

    private func login() throws -> String {
        let r = gh(["api", "user", "--jq", ".login"])
        guard r.ok, !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunError("gh is not authenticated; run gh auth login")
        }
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareClone(_ repo: RepoConfig) throws {
        try RepoClone.sync(repo, env: env)
    }

    private struct GHPR: Decodable {
        struct Author: Decodable {
            let login: String
            let isBot: Bool?
            enum CodingKeys: String, CodingKey { case login, isBot = "is_bot" }
        }
        let number: Int
        let title: String
        let author: Author?
        let isDraft: Bool
        let headRefOid: String
        let additions: Int
        let deletions: Int
    }

    private func listPRs(_ repo: RepoConfig) throws -> [PRInfo] {
        let r = gh(["pr", "list", "-R", repo.slug, "--state", "open", "--limit", "100",
                    "--json", "number,title,author,isDraft,headRefOid,additions,deletions"])
        guard r.ok, let data = r.stdout.data(using: .utf8),
              let rows = try? JSONDecoder().decode([GHPR].self, from: data) else {
            throw RunError("gh pr list failed")
        }
        return rows.map {
            PRInfo(n: $0.number, title: $0.title, author: $0.author?.login ?? "ghost",
                   authorIsBot: $0.author?.isBot ?? false, isDraft: $0.isDraft,
                   headSha: $0.headRefOid, additions: $0.additions, deletions: $0.deletions)
        }
    }

    /// Commit SHAs this user has already reviewed on a PR.
    /// nil when the lookup fails; the PR is then skipped, not the repo.
    private func reviewedHeads(_ repo: RepoConfig, _ n: Int) -> Set<String>? {
        let r = gh(["api", "repos/\(repo.slug)/pulls/\(n)/reviews", "--paginate",
                    "--jq", ".[] | [.user.login, .commit_id] | @tsv"])
        guard r.ok else { return nil }
        var heads = Set<String>()
        for line in r.stdout.split(separator: "\n") {
            let cols = line.split(separator: "\t").map(String.init)
            if cols.count == 2, cols[0] == me { heads.insert(cols[1]) }
        }
        return heads
    }

    /// nil when the permission cannot be read (no push access, or a non-200). That is not cached as
    /// "not a collaborator": the PR is skipped with a reason that says to list authors explicitly.
    private func isCollaborator(_ repo: RepoConfig, login: String) -> Bool? {
        let key = repo.slug + "/" + login
        if let cached = collaboratorCache[key] { return cached }
        let r = gh(["api", "repos/\(repo.slug)/collaborators/\(login)/permission", "--jq", ".permission"])
        guard r.ok else { return nil }
        let value = ["admin", "maintain", "write"].contains(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        collaboratorCache[key] = value
        return value
    }

    private func gh(_ args: [String]) -> ShellResult { Shell.run("gh", args, env: env, timeout: 120) }
    private func git(_ args: [String]) -> ShellResult { Shell.run("git", args, env: env, timeout: 300) }

    // MARK: State

    private func update(_ body: (inout RunState) throws -> Void) throws {
        var run = try store.load(id)
        try body(&run)
        try store.save(run)
    }

    private func printSummary() {
        guard let run = try? store.load(id) else { return }
        for repo in run.repos {
            if let error = repo.error { print("\(repo.slug): error: \(error)") }
            for pr in repo.prs {
                let verdict: String
                switch pr.verdict {
                case .approve?: verdict = "APPROVE"
                case .changes?: verdict = "CHANGES"
                case .skipped?: verdict = "skipped"
                case nil: verdict = "dropped"
                }
                let reason = pr.reason.map { " (\($0))" } ?? ""
                print("\(repo.slug) #\(pr.n) \(pr.author ?? "?"): \(verdict)\(reason)")
            }
        }
        print("tokens: \(run.tokens)")
    }

    static func makeID(_ now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(6).lowercased()
        return f.string(from: now) + "-" + suffix
    }
}
