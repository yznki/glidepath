import Foundation

/// Clone management shared by `init` and `run`. Clones are detached at the default branch and are
/// never used for work; a dirty clone stops the run instead of being reset.
enum RepoClone {
    /// Upper bound for clone and fetch. A stuck network should not hold the run lock for hours.
    static let slowTimeout: TimeInterval = 30 * 60

    static func sync(_ repo: RepoConfig, env: [String: String], home: String = Paths().home) throws {
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
            // HTTPS with gh as the credential helper. `gh repo clone` follows the user's git_protocol, which can be
            // SSH, and an SSH clone can hang for the whole timeout on a machine without working SSH keys.
            let r = git(["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential",
                         "clone", "--filter=blob:none", "--quiet", cloneURL(repo.slug), repo.clone], env, slowTimeout)
            guard r.ok else {
                // Remove what this call created, so the next run starts clean instead of finding a half clone.
                if createdHere { try? fm.removeItem(atPath: repo.clone) }
                throw RunError("clone failed: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            try writeMarker(repo.clone)
        }
        try claim(repo.clone, home: home)
        try excludeGitNexusIndex(repo.clone)
        _ = git(["-C", repo.clone, "config", "credential.helper", "!gh auth git-credential"], env, 30)

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

    static let markerName = "glidepath-clone"
    static let markerText = "created by glidepath; safe to delete with the clone\n"

    /// Whether Glidepath may run git in an existing clone: it made it (marker), or it sits in the default clones folder.
    /// Ownership is checked before any git command touches the folder, so a user's own checkout is never switched.
    static func owns(_ clone: String, home: String) -> Bool {
        FileManager.default.fileExists(atPath: markerPath(clone))
            || clone.hasPrefix(ConfigEditor.clonesDir(home: home) + "/")
    }

    /// Throws for an existing clone Glidepath does not own. A default-folder clone without a marker gets one.
    static func claim(_ clone: String, home: String) throws {
        guard owns(clone, home: home) else { throw notOwned(clone) }
        if !FileManager.default.fileExists(atPath: markerPath(clone)) { try writeMarker(clone) }
    }

    static func notOwned(_ clone: String) -> RunError {
        RunError("\(clone) is not a Glidepath clone. Glidepath only reviews in a folder it created, so it never switches branches under your own work. Remove `clone` from this repo's config to use the default, or point it at an empty folder.")
    }

    static func markerPath(_ clone: String) -> String {
        clone + "/.git/" + markerName
    }

    private static func writeMarker(_ clone: String) throws {
        try markerText.write(toFile: markerPath(clone), atomically: true, encoding: .utf8)
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

    static func cloneURL(_ slug: String) -> String {
        "https://github.com/\(slug).git"
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

/// `glidepath run [--dry-run] [--repo slug] [--scheduled] [--max-prs N]`.
enum RunCommand {
    /// The `--max-prs` value: a whole number of 1 or more, else nil.
    static func maxPRs(_ raw: String) -> Int? {
        guard let n = Int(raw), n >= 1 else { return nil }
        return n
    }

    static func main(_ args: [String]) -> Int32 {
        let a = Args(args, valued: ["--repo", "--max-prs"])
        let paths = Paths()
        if a.has("--scheduled") && Pause.isPaused(paths) {
            print("paused; scheduled run skipped")
            return 0
        }
        if let message = HookRefusal.message(paths: paths) {
            eprint(message)
            return 1
        }
        var config: Config
        do {
            config = try Config.load(paths)
        } catch {
            eprint("\(error)")
            return 1
        }
        // The limit for this run only: the config file keeps its own value.
        if a.has("--max-prs") || a.value("--max-prs") != nil {
            guard let raw = a.value("--max-prs"), let n = maxPRs(raw) else {
                eprint("--max-prs needs a whole number of 1 or more")
                return 1
            }
            config.limits.maxPRsPerRun = n
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
            eprint("no repos configured; run glidepath init")
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
        // A group of its own, so Stop can signal this runner and the review sessions it starts together.
        _ = setpgid(0, 0)
        try? "\(getpid())".write(toFile: paths.pidFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: paths.pidFile) }
        let runner = Runner(paths: paths, config: config, dryRun: a.has("--dry-run") || config.dryRun)
        runner.scheduled = a.has("--scheduled")
        return withExtendedLifetime(lock) { runner.execute(repos: repos) }
    }
}

/// `glidepath review owner/name N [--dry-run] [--again]`: reviews one open PR now, including one over
/// `max_changed_lines`. Every other filter still applies. The run lock is taken, as for a sweep.
enum ReviewCommand {
    static func main(_ args: [String]) -> Int32 {
        let switches = Set(args.filter { $0.hasPrefix("--") })
        let positional = args.filter { !$0.hasPrefix("--") }
        let usage = "usage: glidepath review owner/name N [--dry-run] [--again]"
        guard switches.isSubset(of: ["--dry-run", "--again"]), positional.count == 2,
              RepoConfig.isValidSlug(positional[0]), let n = Int(positional[1]), n > 0, String(n) == positional[1] else {
            eprint(usage)
            return 2
        }
        let paths = Paths()
        if let message = HookRefusal.message(paths: paths) {
            eprint(message)
            return 1
        }
        let config: Config
        do {
            config = try Config.load(paths)
        } catch {
            eprint("\(error)")
            return 1
        }
        guard let repo = config.repos.first(where: { $0.slug == positional[0] }) else {
            eprint("repo \(positional[0]) is not in the config")
            return 1
        }
        let lock: RunLock
        do {
            guard let held = try RunLock.acquire(paths.lockFile) else {
                print("A review run is in progress; try again when it ends")
                return 1
            }
            lock = held
        } catch {
            eprint("\(error)")
            return 1
        }
        // Same process group as a sweep, so Stop reaches the review session too.
        _ = setpgid(0, 0)
        try? "\(getpid())".write(toFile: paths.pidFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: paths.pidFile) }
        let runner = Runner(paths: paths, config: config, dryRun: switches.contains("--dry-run") || config.dryRun)
        runner.onlyPR = (repo.slug, n)
        runner.again = switches.contains("--again")
        return withExtendedLifetime(lock) { runner.execute(repos: [repo]) }
    }
}

/// Refuses to start when the user's own hooks would run inside a review session.
enum HookRefusal {
    static func message(paths: Paths) -> String? {
        let conflicts = Claude.hookConflicts(paths: paths)
        guard !conflicts.isEmpty else { return nil }
        let lines = conflicts.map { "  \($0.file): \($0.events.joined(separator: ", "))" }
        return ("refusing to run: these files define hooks that would run inside review sessions:\n"
            + lines.joined(separator: "\n")
            + "\nMove those hooks out of the file, or scope them to a project that review sessions do not use,"
            + "\nthen run again. SessionStart, UserPromptSubmit and Stop hooks are allowed.")
    }
}

/// The skill and rubric, read from the installed share folder, and the repo's rules file if any.
enum SkillText {
    /// The installed skill folder: share/glidepath next to the binary, or the skill/glidepath dev folder.
    static func installedDir() throws -> String {
        guard let dir = InitCommand.findInstalledDir(relative: "share/glidepath", fallback: "skill/glidepath",
                                                     requiredFile: "SKILL.md", from: InitCommand.binaryPath()) else {
            throw RunError("skill files not found; reinstall glidepath")
        }
        return dir
    }

    /// rubric.md, with the repo's rules file appended when there is one. Reviewers read this copy from scratch.
    static func rubric(dir: String, rules: String?, rulesMode: RulesMode) throws -> String {
        var text = try String(contentsOfFile: dir + "/rubric.md", encoding: .utf8)
        if let rules {
            let body = try String(contentsOfFile: rules, encoding: .utf8)
            text += "\n\n# Repo rules (\(rulesMode.rawValue))\n\n" + body
        }
        return text
    }

    static func load(paths: Paths, rules: String?, rulesMode: RulesMode) throws -> String {
        let dir = try installedDir()
        let skill = try String(contentsOfFile: dir + "/SKILL.md", encoding: .utf8)
        return skill + "\n\n# Review rubric\n\n" + (try rubric(dir: dir, rules: rules, rulesMode: rulesMode))
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
    /// Set by `glidepath review`: the one PR to consider, and whether an already reviewed head is reviewed again.
    var onlyPR: (slug: String, n: Int)?
    var again = false
    /// Set when the PR named by `onlyPR` was skipped as the user's own, so the summary can say how to review it.
    private var namedPRIsOwn = false
    /// A scheduled sweep (launchd's `run --scheduled`). Only these stop at the monthly token budget.
    var scheduled = false
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
    /// gh reads its config from $XDG_CONFIG_HOME/gh when that is set, which would hide the user's sign-in
    /// when glidepath's config folder is moved. Pin gh to the real HOME location unless told otherwise.
    static func pinGitHubConfig(_ env: [String: String], home: String) -> [String: String] {
        var out = env
        if out["GH_CONFIG_DIR"] == nil { out["GH_CONFIG_DIR"] = home + "/.config/gh" }
        return out
    }

    static func environment(_ paths: Paths) -> [String: String] {
        var env = pinGitHubConfig(ProcessInfo.processInfo.environment, home: paths.home)
        if let path = jobPath(paths) { env["PATH"] = path }
        return env
    }

    /// The PATH recorded in the installed launchd job. nil when no job is installed.
    static func jobPath(_ paths: Paths) -> String? {
        guard let data = FileManager.default.contents(atPath: paths.plistFile),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let vars = dict["EnvironmentVariables"] as? [String: String] else { return nil }
        return vars["PATH"]
    }

    func execute(repos: [RepoConfig]) -> Int32 {
        let now = Date()
        id = Runner.makeID(now)
        do {
            var fresh = RunState.new(id: id, now: now, kind: onlyPR == nil ? nil : "review")
            if let target = onlyPR, !dryRun, let previous = try? store.loadCurrent() {
                fresh.carryRows(from: previous, except: target)
            }
            try store.save(fresh)
            if !dryRun { try store.makeCurrent(id) }
        } catch {
            eprint("cannot create run \(id): \(error)")
            return 1
        }
        pruneScratch(now: now)
        ReviewText.prune(root: paths.stateDir, now: now)
        print("run \(id)\(dryRun ? " (dry run)" : "")")
        if scheduled, TokenBudget.blocks(config, used: TokenBudget.used(store.loadAll(), now: now)) {
            try? store.mutate(id) { $0.finish(at: Date(), error: "Monthly token budget reached") }
            print("Monthly token budget reached; scheduled sweep skipped")
            return 1
        }

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
                    try? update { run in
                        run.phase = nil
                        run.setRepoError(repo.slug, "\(error)")
                    }
                }
            }
        } catch {
            failed = true
            print("\(error)")
            try? update { $0.error = "\(error)" }
        }

        let earlier = failed ? store.loadAll() : []
        try? update { run in
            run.finish(at: Date(), error: run.error)
            run.tokens = totalTokens
            if failed { run.carryOver(from: earlier) }
        }
        printSummary()
        if namedPRIsOwn {
            print("To review your own PRs, set include_own = true under this repo in \(paths.configFile)")
        }
        return failed ? 1 : 0
    }

    // MARK: Per repo

    /// Returns the tokens this repo's session used.
    private func process(_ repo: RepoConfig) throws -> Int {
        try prepareClone(repo)
        setPhase("listing PRs in \(repo.slug)")
        var prs = try listPRs(repo)
        if let target = onlyPR {
            // `glidepath review`: only the named PR is considered, and only it gets the size override.
            prs = prs.filter { $0.n == target.n }
            if prs.isEmpty { print("\(repo.slug) #\(target.n): not an open PR") }
        }

        var kept: [PRInfo] = []
        var skipped: [(PRInfo, String)] = []
        let drafts = Drafts.all(paths)
        for pr in prs {
            let again = self.again && self.onlyPR?.n == pr.n
            let heldHeads = Set(drafts.filter { $0.draft.slug == repo.slug && $0.draft.n == pr.n }.map(\.draft.head))
            let decision = PRFilter.evaluate(
                pr, me: me, includeOwn: repo.includeOwn, reviewDrafts: repo.reviewDrafts ?? config.reviewDrafts,
                includeBots: config.includeBots, authors: repo.authors,
                limits: Runner.limits(config.limits, for: pr.n, reviewing: onlyPR?.n),
                draftHeads: again ? [] : heldHeads,
                isCollaborator: { self.isCollaborator(repo, login: pr.author) },
                reviewedHeads: { again ? Set<String>() : self.reviewedHeads(repo, pr.n) })
            switch decision {
            case .keep where kept.count < config.limits.maxPRsPerRun:
                kept.append(pr)
            case .keep:
                skipped.append((pr, PRFilter.heldForNextSweep(cap: config.limits.maxPRsPerRun)))
            case .skip(let reason):
                skipped.append((pr, reason))
                if onlyPR?.n == pr.n, reason == PRFilter.ownPRReason { namedPRIsOwn = true }
            }
        }

        let flagged = flaggedNumbers(repo, kept)
        // The index is refreshed only for a repo that has something to review, so an idle repo costs nothing.
        var gitnexus = gitnexusEnabled(repo)
        if !kept.isEmpty, gitnexus, repo.gitnexusRefresh {
            setPhase("indexing \(repo.slug)")
            gitnexus = refreshGitNexus(repo)
        }

        try update { run in
            run.phase = nil
            run.ensureRepo(repo.slug)
            for (pr, reason) in skipped {
                try run.setPR(repo: repo.slug, n: pr.n, stage: nil, author: pr.author, title: pr.title,
                              verdict: .skipped, reason: reason)
                run.setSize(repo: repo.slug, n: pr.n, changedLines: pr.changedLines,
                            skippedForSize: reason.hasPrefix(PRFilter.tooLargeReason))
                run.setDraftPR(repo: repo.slug, n: pr.n, isDraft: pr.isDraft)
            }
            for pr in kept {
                try run.setPR(repo: repo.slug, n: pr.n, stage: nil, author: pr.author, title: pr.title,
                              verdict: nil, reason: nil)
                run.setSize(repo: repo.slug, n: pr.n, changedLines: pr.changedLines, skippedForSize: false)
                run.setDraftPR(repo: repo.slug, n: pr.n, isDraft: pr.isDraft)
                if flagged.contains(pr.n) { try run.setFlagged(repo: repo.slug, n: pr.n) }
            }
        }
        guard !kept.isEmpty else { return 0 }
        return try invokeReview(repo, kept: kept, gitnexus: gitnexus)
    }

    /// The limits for one PR. Only the PR named by `glidepath review` loses the size limit; every other filter applies.
    static func limits(_ base: Limits, for n: Int, reviewing target: Int?) -> Limits {
        var out = base
        if target == n { out.maxChangedLines = Int.max }
        return out
    }

    /// Re-indexes the clone so GitNexus answers from the code that is checked out. Failure or the 10-minute limit
    /// turns GitNexus off for this repo in this run; the sweep carries on without it.
    private func refreshGitNexus(_ repo: RepoConfig) -> Bool {
        let r = Shell.run("gitnexus", ["analyze", "--index-only"], cwd: repo.clone, env: env, timeout: 600)
        let output = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty { print(output) }
        if r.ok { return true }
        print("\(repo.slug): gitnexus refresh failed (exit \(r.status)); reviewing this repo without GitNexus")
        return false
    }

    /// The PRs whose changed files start with a `flag_paths` prefix. The file list comes from gh, never the model.
    /// A lookup that fails leaves the PR unflagged here; `post` still computes the note from a fresh list.
    private func flaggedNumbers(_ repo: RepoConfig, _ kept: [PRInfo]) -> Set<Int> {
        guard !repo.flagPaths.isEmpty else { return [] }
        var out = Set<Int>()
        for pr in kept {
            guard let files = try? GH.changedFiles(repo.slug, pr.n, env: env) else {
                print("\(repo.slug) #\(pr.n): could not read changed files for flag_paths")
                continue
            }
            if !FlagPaths.matches(files, prefixes: repo.flagPaths).isEmpty { out.insert(pr.n) }
        }
        return out
    }

    private func invokeReview(_ repo: RepoConfig, kept: [PRInfo], gitnexus: Bool) throws -> Int {
        let fm = FileManager.default
        let numbers = kept.map(\.n)
        let session = UUID().uuidString.lowercased()
        let scratch = paths.scratchDir + "/" + id + "/" + repo.owner + "-" + repo.name
        try fm.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        // Reviewers may read only the clone and the scratch folder, so the rubric (with the repo rules) is copied here
        // for them. The skill's step 3 points at this file.
        let rubric = try SkillText.rubric(dir: SkillText.installedDir(), rules: repo.rules, rulesMode: repo.rulesMode)
        try rubric.write(toFile: scratch + "/rubric.md", atomically: true, encoding: .utf8)
        let mcpPath = scratch + "/mcp.json"
        try Claude.mcpConfig(gitnexus: gitnexus).write(toFile: mcpPath, atomically: true, encoding: .utf8)

        // The skill and its rubric are read here and passed as the system prompt. No slash command is used,
        // so nothing can be resolved to another skill.
        let skill = try SkillText.load(paths: paths, rules: repo.rules, rulesMode: repo.rulesMode)
        let allowlist = Claude.allowlist(clone: repo.clone, scratch: scratch, rules: repo.rules, gitnexus: gitnexus)
        let prompt = [
            "Review run.",
            "repo=\(repo.slug)", "prs=\(numbers.map(String.init).joined(separator: ","))",
            "run=\(id)", "scratch=\(scratch)", "gitnexus=\(gitnexus ? "on" : "off")",
            "rules=\(repo.rules == nil ? "none" : "included")", "rules_mode=\(repo.rulesMode.rawValue)",
            "split_over=\(config.limits.splitOverLines)",
            "dry_run=\(dryRun)",
        ].joined(separator: " ") + (config.strictness.promptLine.isEmpty ? "" : " " + config.strictness.promptLine)
        let binding = RunBinding(runId: id, repo: repo.slug, scratch: scratch, clone: repo.clone, dryRun: dryRun)
        let args = Claude.arguments(
            prompt: prompt, systemPrompt: skill, sessionId: session, scratch: scratch, mcpConfig: mcpPath,
            agents: Claude.agentsJSON(),
            settings: Claude.hookSettingsJSON(binary: InitCommand.binaryPath()),
            allowlist: allowlist, model: config.model.rawValue)
        var childEnv = Claude.childEnvironment(parent: env, binding: binding.environment)
        childEnv["PATH"] = Claude.pathPrepending(InitCommand.runningBinaryDirectory(), to: childEnv["PATH"])
        childEnv["GLIDEPATH_STATE_DIR"] = paths.stateDir
        childEnv["GLIDEPATH_CONFIG_FILE"] = paths.configFile

        // The session id and its directory go in the run file, so the app can read this session's transcript while it runs.
        try? update {
            $0.sessionId = session
            $0.sessionCwd = repo.clone
        }
        print("\(repo.slug): reviewing \(numbers.map { "#\($0)" }.joined(separator: " "))")
        // The scheduled log is not a terminal and keeps the full tool lists for later audit. An interactive run
        // skips them, since they repeat on every review.
        if isatty(STDOUT_FILENO) == 0 {
            print("allowlist: " + allowlist.joined(separator: ","))
            print("disallowed: " + Claude.disallowed.joined(separator: ","))
        }
        let result = Shell.run("claude", args, cwd: repo.clone, env: childEnv, timeout: 3600)
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

    /// Scratch directories older than seven days go, except the current run's.
    func pruneScratch(now: Date) {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        for name in (try? fm.contentsOfDirectory(atPath: paths.scratchDir)) ?? [] where name != id {
            let dir = paths.scratchDir + "/" + name
            if let attrs = try? fm.attributesOfItem(atPath: dir),
               let modified = attrs[.modificationDate] as? Date, modified < cutoff {
                try? fm.removeItem(atPath: dir)
            }
        }
    }

    private func gitnexusEnabled(_ repo: RepoConfig) -> Bool {
        Claude.gitnexusEnabled(mode: repo.gitnexus, authors: repo.authors,
                               binaryFound: Shell.find("gitnexus", path: env["PATH"]) != nil)
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
        try store.mutate(id, body)
    }

    /// Shows the app what the runner is doing before any PR is recorded. Best effort: a failed write only loses the line.
    private func setPhase(_ text: String?) {
        try? update { $0.phase = text }
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
        let rows = run.repos.flatMap(\.prs)
        if rows.isEmpty {
            print("no open PRs to review")
        } else if !rows.contains(where: { $0.verdict == .approve || $0.verdict == .changes }) {
            print("0 PRs reviewed (\(rows.filter { $0.verdict == .skipped }.count) skipped)")
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
