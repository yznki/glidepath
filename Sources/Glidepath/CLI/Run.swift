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

/// One PR a by-hand review names.
struct PRRef: Hashable {
    let slug: String
    let n: Int
}

/// What `glidepath review` reviews: the named PRs, or every open PR by one author.
enum ReviewTarget: Equatable {
    /// Never empty. Duplicates are removed and the order is kept.
    case prs([PRRef])
    case author(String)

    /// Whether a PR is in this target. Slugs and logins match case-insensitively. An author target ignores the slug.
    func includes(slug: String, n: Int, author: String?) -> Bool {
        switch self {
        case .prs(let refs):
            return refs.contains { $0.n == n && $0.slug.caseInsensitiveCompare(slug) == .orderedSame }
        case .author(let login):
            guard let author else { return false }
            return author.caseInsensitiveCompare(login) == .orderedSame
        }
    }

    /// The PRs a review names, read left to right. A slug token sets the repo for the numbers after it. A number (an
    /// optional `#`, no leading zero) is a PR in that repo, or in `defaultRepo` before any slug. A GitHub PR link is a
    /// PR on its own and leaves the repo as it was. Anything else, a slug with no number after it, or no PRs gives nil.
    /// Duplicates (slugs ignoring case) are dropped.
    static func parsePRs(_ tokens: [String], defaultRepo: String? = nil) -> [PRRef]? {
        var refs: [PRRef] = []
        var repo = defaultRepo
        var slugAwaitingNumber = false
        for token in tokens {
            if RepoConfig.isValidSlug(token) {
                if slugAwaitingNumber { return nil }
                repo = token
                slugAwaitingNumber = true
                continue
            }
            let ref: PRRef
            if let n = number(token) {
                guard let repo else { return nil }
                ref = PRRef(slug: repo, n: n)
                slugAwaitingNumber = false
            } else if let link = link(token) {
                ref = link
            } else {
                return nil
            }
            if !refs.contains(where: { $0.n == ref.n && $0.slug.caseInsensitiveCompare(ref.slug) == .orderedSame }) {
                refs.append(ref)
            }
        }
        guard !slugAwaitingNumber, !refs.isEmpty else { return nil }
        return refs
    }

    /// A PR number: a positive whole number, written without leading zeros, with an optional `#`.
    private static func number(_ token: String) -> Int? {
        let digits = token.hasPrefix("#") ? String(token.dropFirst()) : token
        guard let n = Int(digits), n > 0, String(n) == digits else { return nil }
        return n
    }

    /// The PR a GitHub pull request link names, or nil.
    private static func link(_ url: String) -> PRRef? {
        let pattern = #"\Ahttps?://(www\.)?github\.com/([^/\s]+/[^/\s]+)/pull/([0-9]+)([/?#].*)?\z"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let slugRange = Range(match.range(at: 2), in: url),
              let numberRange = Range(match.range(at: 3), in: url) else { return nil }
        let slug = String(url[slugRange])
        guard RepoConfig.isValidSlug(slug), let n = Int(url[numberRange]), n > 0 else { return nil }
        return PRRef(slug: slug, n: n)
    }

    /// What the run file records for this target: "author:<login>", or "prs:" and `owner/name#n` joined with commas.
    var runTarget: String {
        switch self {
        case .prs(let refs): return "prs:" + refs.map { "\($0.slug)#\($0.n)" }.joined(separator: ",")
        case .author(let login): return "author:\(login)"
        }
    }

    /// The CLI arguments the app spawns for this target: each repo's slug, then its numbers, in first-seen order.
    var arguments: [String] {
        switch self {
        case .prs(let refs):
            var slugs: [String] = []
            for ref in refs where !slugs.contains(where: { $0.caseInsensitiveCompare(ref.slug) == .orderedSame }) {
                slugs.append(ref.slug)
            }
            return ["review"] + slugs.flatMap { slug in
                [slug] + refs.filter { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }.map { String($0.n) }
            }
        case .author(let login): return ["review", "--author", login]
        }
    }
}

/// `glidepath review owner/name N [N...] | PR-URL [PR-URL...] | --author login [--repo owner/name] [--dry-run] [--again]`:
/// reviews the named PRs now, including ones over `max_changed_lines`, or every open PR by one author. A by-hand review
/// ignores the authors list, the size limit, the per-sweep cap, and the draft and bot skips. A named PR is reviewed even
/// when it is yours; author mode still skips your own PRs unless `include_own` is set. Both still skip PRs reviewed at
/// this head and PRs with a held draft at this head. The run lock is taken once, as for a sweep.
enum ReviewCommand {
    static let usage = "usage: glidepath review owner/name N [N...] | PR-URL [PR-URL...] | --author login [--repo owner/name]  [--dry-run] [--again]"

    /// The parsed arguments, or nil when they are not one of the three forms.
    static func parse(_ args: [String]) -> (target: ReviewTarget, repo: String?, dryRun: Bool, again: Bool)? {
        var positional: [String] = []
        var author: String?
        var repo: String?
        var dryRun = false
        var again = false
        var i = 0
        while i < args.count {
            let token = args[i]
            i += 1
            switch token {
            case "--author", "--repo":
                guard i < args.count else { return nil }
                if token == "--author" { author = args[i] } else { repo = args[i] }
                i += 1
            case "--dry-run":
                dryRun = true
            case "--again":
                again = true
            default:
                if token.hasPrefix("--") { return nil }
                positional.append(token)
            }
        }
        guard let login = author else {
            guard repo == nil, let refs = ReviewTarget.parsePRs(positional) else { return nil }
            return (.prs(refs), nil, dryRun, again)
        }
        guard positional.isEmpty, (try? ConfigEditor.validateLogin(login)) != nil else { return nil }
        if let repo, !RepoConfig.isValidSlug(repo) { return nil }
        return (.author(login), repo, dryRun, again)
    }

    static func main(_ args: [String]) -> Int32 {
        guard let parsed = parse(args) else {
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
        var target = parsed.target
        let repos: [RepoConfig]
        switch parsed.target {
        case .prs(let refs):
            // The refs take the config's spelling of each slug; the repos run in config order.
            var named: [PRRef] = []
            for ref in refs {
                guard let repo = config.repos.first(where: { $0.slug.caseInsensitiveCompare(ref.slug) == .orderedSame }) else {
                    eprint("repo \(ref.slug) is not in the config")
                    return 1
                }
                named.append(PRRef(slug: repo.slug, n: ref.n))
            }
            repos = config.repos.filter { repo in named.contains { $0.slug == repo.slug } }
            target = .prs(named)
        case .author:
            guard !config.repos.isEmpty else {
                eprint("no repos configured; run glidepath init")
                return 1
            }
            if let slug = parsed.repo {
                let narrowed = config.repos.filter { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }
                guard !narrowed.isEmpty else {
                    eprint("repo \(slug) is not in the config")
                    return 1
                }
                repos = narrowed
            } else {
                repos = config.repos
            }
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
        let runner = Runner(paths: paths, config: config, dryRun: parsed.dryRun || config.dryRun)
        runner.target = target
        runner.again = parsed.again
        return withExtendedLifetime(lock) { runner.execute(repos: repos) }
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
    /// Set by `glidepath review`: the PR or author to consider. nil for a sweep.
    var target: ReviewTarget?
    /// Set by `glidepath review --again`: an already reviewed head is reviewed again. Ignored for a sweep.
    var again = false
    /// Set when an author review skipped one of the user's own PRs, so the summary can say how to include them.
    private var ownPRSkipped = false
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
            var fresh = RunState.new(id: id, now: now, kind: target == nil ? nil : "review", target: target?.runTarget)
            if target != nil, !dryRun, let previous = try? store.loadCurrent() {
                fresh.carryRows(from: previous)
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
        if ownPRSkipped {
            print("To review your own PRs, set include_own = true under this repo in \(paths.configFile)")
        }
        return failed ? 1 : 0
    }

    // MARK: Per repo

    /// Whether the user's own PRs are considered: always for a named PR, else only when the repo sets `include_own`.
    static func includeOwn(_ repo: RepoConfig, target: ReviewTarget?) -> Bool {
        if case .prs? = target { return true }
        return repo.includeOwn
    }

    /// Returns the tokens this repo's session used.
    private func process(_ repo: RepoConfig) throws -> Int {
        setPhase("listing PRs in \(repo.slug)")
        var prs = try Runner.openPRs(repo.slug, env: env)
        if let target {
            // `glidepath review`: only the PRs in the target are considered, and they skip the by-hand filters.
            prs = prs.filter { target.includes(slug: repo.slug, n: $0.n, author: $0.author) }
            if case .prs(let refs) = target {
                for ref in refs where ref.slug.caseInsensitiveCompare(repo.slug) == .orderedSame && !prs.contains(where: { $0.n == ref.n }) {
                    print("\(repo.slug) #\(ref.n): not an open PR")
                }
            }
        }
        // A review with nothing to consider in this repo clones nothing. A sweep always syncs the clone.
        if target == nil || !prs.isEmpty { try prepareClone(repo) }

        var kept: [PRInfo] = []
        var skipped: [(PRInfo, String)] = []
        let drafts = Drafts.all(paths)
        let byHand = target != nil
        for pr in prs {
            let again = self.again && byHand
            let heldHeads = Set(drafts.filter { $0.draft.slug == repo.slug && $0.draft.n == pr.n }.map(\.draft.head))
            let decision = PRFilter.evaluate(
                pr, me: me, includeOwn: Runner.includeOwn(repo, target: target), reviewDrafts: repo.reviewDrafts ?? config.reviewDrafts,
                includeBots: config.includeBots, byHand: byHand, authors: repo.authors, limits: config.limits,
                draftHeads: again ? [] : heldHeads,
                isCollaborator: { self.isCollaborator(repo, login: pr.author) },
                reviewedHeads: { again ? Set<String>() : self.reviewedHeads(repo, pr.n) })
            switch decision {
            case .keep where byHand || kept.count < config.limits.maxPRsPerRun:
                kept.append(pr)
            case .keep:
                skipped.append((pr, PRFilter.heldForNextSweep(cap: config.limits.maxPRsPerRun)))
            case .skip(let reason):
                skipped.append((pr, reason))
                if case .author? = target, reason == PRFilter.ownPRReason { ownPRSkipped = true }
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
            run.dropCarried(repo: repo.slug, numbers: Set(prs.map(\.n)))
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
        // Runs after the session, and also when it could not start, so no kept row is left with nothing said.
        defer {
            try? update { $0.noteUnstamped(repo: repo.slug, numbers: Set(kept.map(\.n)),
                                           reason: "review session ended without a verdict; see the log") }
        }
        return try invokeReview(repo, kept: kept, gitnexus: gitnexus)
    }

    /// Re-indexes the clone so GitNexus answers from the code that is checked out. Failure or the 10-minute limit
    /// turns GitNexus off for this repo in this run; the sweep carries on without it.
    private func refreshGitNexus(_ repo: RepoConfig) -> Bool {
        let r = Shell.run("gitnexus", ["analyze", "--index-only"], cwd: repo.clone, env: env, timeout: 600)
        let output = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if r.ok {
            let kept = Self.gitNexusLogLines(output)
            if !kept.isEmpty { print(kept.joined(separator: "\n")) }
            return true
        }
        if !output.isEmpty { print(output) }
        print("\(repo.slug): gitnexus refresh failed (exit \(r.status)); reviewing this repo without GitNexus")
        return false
    }

    /// On success: the warn and error JSON log lines (at most the last 20), and the last 8 other lines. Routine JSON
    /// log lines say nothing a reader needs. Kept lines stay in their original order.
    static func gitNexusLogLines(_ output: String) -> [String] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        func isJSON(_ line: String) -> Bool { line.hasPrefix("{\"level\"") }
        func isWarning(_ line: String) -> Bool {
            guard let r = line.range(of: #""level":\d+"#, options: .regularExpression),
                  let level = Int(line[r].dropFirst(#""level":"#.count)) else { return false }
            return level >= 40
        }
        let warnings = lines.indices.filter { isJSON(lines[$0]) && isWarning(lines[$0]) }.suffix(20)
        let text = lines.indices.filter { !isJSON(lines[$0]) }.suffix(8)
        let keep = Set(warnings).union(text)
        return lines.indices.filter { keep.contains($0) }.map { lines[$0] }
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
            agents: Claude.agentsJSON(gitnexus: gitnexus),
            settings: Claude.hookSettingsJSON(binary: InitCommand.binaryPath()),
            allowlist: allowlist, model: config.model.rawValue)
        var childEnv = Claude.childEnvironment(parent: env, binding: binding.environment)
        childEnv["PATH"] = Claude.pathPrepending(InitCommand.runningBinaryDirectory(), to: childEnv["PATH"])
        childEnv["GLIDEPATH_STATE_DIR"] = paths.stateDir
        childEnv["GLIDEPATH_CONFIG_FILE"] = paths.configFile
        if let claudeDir = config.claudeConfigDir { childEnv["CLAUDE_CONFIG_DIR"] = claudeDir }
        // The session's agents must finish; the runner's 3600 s session timeout still bounds the run.
        childEnv = Claude.waitingForAgents(childEnv)

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
        // stream-json gives every event, including the rate-limit reports the usage guard reads. The log keeps the
        // session's final text, which is what the owner notes are read from.
        let result = Shell.run("claude", args + ["--output-format", "stream-json", "--verbose"], cwd: repo.clone,
                               env: childEnv, timeout: 3600)
        let logPath = scratch + "/claude.log"
        let text = UsageGuard.resultText(stream: result.stdout) ?? result.stdout
        try? (text + result.stderr).write(toFile: logPath, atomically: true, encoding: .utf8)
        if dryRun { print(text) }
        Runner.recordUsage(stream: result.stdout, paths: paths)

        let usage = Transcript.usage(paths: paths, cwd: repo.clone, sessionId: session, keptPRs: Set(numbers),
                                     claudeDir: config.claudeConfigDir)
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

    /// Keeps the newest rate-limit window of each type, so the usage guard knows how much Claude usage is left.
    static func recordUsage(stream: String, paths: Paths) {
        var state = UsageState.load(paths)
        state.record(UsageGuard.events(stream: stream, now: Date()))
        try? state.save(paths)
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
        // Waits for a tend round that is working in the same clone.
        let lock = try RunLock.acquire(paths.cloneLock(repo.slug), wait: true)
        try withExtendedLifetime(lock) { try RepoClone.sync(repo, env: env) }
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

    /// The open PRs of a repo, from `gh pr list`. Throws when gh fails. The app lists them too, for the Review sheet.
    static func openPRs(_ slug: String, env: [String: String]) throws -> [PRInfo] {
        let r = Shell.run("gh", ["pr", "list", "-R", slug, "--state", "open", "--limit", "100",
                                 "--json", "number,title,author,isDraft,headRefOid,additions,deletions"],
                          env: env, timeout: 120)
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
        if rows.isEmpty && run.repos.allSatisfy({ $0.error == nil }) {
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

    /// The day part of a run id, `yyyyMMdd`, in local time. Ids of one day share it.
    static func dayPrefix(_ now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: now)
    }
}
