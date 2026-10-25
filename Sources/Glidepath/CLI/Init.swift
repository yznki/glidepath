import Foundation

/// `glidepath init`: checks requirements, writes config, clones, installs the skill, the app link
/// and the LaunchAgent, then ends with a dry run so the user sees output before anything is posted.
enum InitCommand {
    static func main(_ args: [String]) -> Int32 {
        let a = Args(args, valued: ["--repo", "--clone"])
        if a.has("--refresh") { return refresh(holdingLock: a.has("--holding-lock")) }
        let paths = Paths()
        let fm = FileManager.default

        print("Checking requirements")
        let missing = Checks.tools().filter { !$0.ok }
        for item in missing { print("FAIL  \(item.name): \(item.fix)") }
        guard missing.isEmpty else { return 1 }

        let config: Config
        do {
            if fm.fileExists(atPath: paths.configFile) {
                config = try Config.load(paths)
                print("Using existing config at \(paths.configFile)")
            } else {
                let slug: String?
                if let flag = a.value("--repo") {
                    slug = repoChoice(answer: flag, suggestion: nil)
                } else {
                    slug = askForRepo(suggestion: currentFolderRepo())
                }
                guard let slug else {
                    eprint(repoNeededMessage)
                    return 2
                }
                let clone = a.value("--clone").map(paths.expand)
                    ?? paths.home + "/glidepath/clones/" + slug.replacingOccurrences(of: "/", with: "-")
                guard clone.hasPrefix("/") else {
                    eprint("--clone must be an absolute path or start with ~/")
                    return 2
                }
                let repo = RepoConfig(slug: slug, clone: clone, posting: .draft)
                config = Config.newSetup(schedule: Config.defaultSchedule.compactMap(ScheduleTime.init), repos: [repo])
                try fm.createDirectory(atPath: (paths.configFile as NSString).deletingLastPathComponent,
                                       withIntermediateDirectories: true)
                try config.render().write(toFile: paths.configFile, atomically: true, encoding: .utf8)
                print("Wrote config \(paths.configFile)")
            }
            guard !config.repos.isEmpty else {
                eprint("no [[repo]] in config; add one, then run init again")
                return 2
            }
        } catch {
            eprint("\(error)")
            return 1
        }

        let env = ProcessInfo.processInfo.environment
        for repo in config.repos {
            do {
                try RepoClone.sync(repo, env: env)
                print("Clone ready: \(repo.clone)")
            } catch {
                eprint("\(repo.slug): \(error)")
                return 1
            }
        }

        let binary = stableBinary(runningBinary: binaryPath())
        guard let skill = findInstalledDir(relative: "share/glidepath", fallback: "skill/glidepath",
                                           requiredFile: "SKILL.md", from: binary) else {
            eprint("skill files not found next to \(binary)")
            return 1
        }
        do {
            try installSkill(from: skill, to: paths.skillDir)
            print("Installed skill to \(paths.skillDir)")
        } catch {
            eprint("could not install skill: \(error)")
            return 1
        }

        if let app = findApp(from: binary) {
            do {
                try linkApp(InstallKind.appTarget(binary: binary, app: app), at: paths.appLink)
                print("Linked \(paths.appLink)")
            } catch {
                eprint("could not link the app: \(error.localizedDescription)")
            }
        } else {
            print("Menu bar app not found next to the binary; skipped the app link")
        }

        do {
            try installJob(paths: paths, config: config, binary: binary,
                           path: GitNexus.jobPath(base: ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                                                  home: paths.home))
            print("Scheduled \(config.schedule.map(\.text).joined(separator: ", ")) via \(paths.plistFile)")
        } catch {
            eprint("could not install the scheduled job: \(error)")
            return 1
        }

        print("Dry run (posts nothing):")
        let slug = config.repos[0].slug
        // Output streams as the run produces it, so the first review is visible while it works.
        let status = Shell.inherit(binary, ["run", "--dry-run", "--repo", slug], env: env)
        guard status == 0 else {
            print("Dry run failed; fix the issue above, then run glidepath doctor.")
            return 1
        }
        print(doneLine(config.repos[0].posting))
        return 0
    }

    /// The last line of init, worded by what the posting mode does on GitHub.
    static func doneLine(_ posting: Posting) -> String {
        switch posting {
        case .draft:
            return "Done. Scheduled reviews are held as drafts on this Mac; nothing reaches GitHub until you post one (glidepath drafts post, or from the app)."
        case .comment:
            return "Done. Scheduled reviews post to GitHub as COMMENT reviews, each starting with its verdict line."
        case .review:
            return "Done. Scheduled reviews post to GitHub as APPROVE or REQUEST_CHANGES reviews."
        }
    }

    static let repoNeededMessage = "init needs a repo as owner/name, for example: glidepath init --repo acme/api"

    /// The repo init settles on for one answer. An empty answer takes the suggestion, if there is a valid one.
    /// Anything else must be owner/name. nil when there is no valid repo.
    static func repoChoice(answer: String, suggestion: String?) -> String? {
        let typed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return suggestion.flatMap { RepoConfig.isValidSlug($0) ? $0 : nil } }
        return RepoConfig.isValidSlug(typed) ? typed : nil
    }

    /// Asks up to three times. nil at end of input or after three answers that are not owner/name.
    private static func askForRepo(suggestion: String?) -> String? {
        let text = suggestion.map { "GitHub repo to review (owner/name) [\($0)]: " } ?? "GitHub repo to review (owner/name): "
        for _ in 0..<3 {
            guard let answer = prompt(text) else { return nil }
            if let slug = repoChoice(answer: answer, suggestion: suggestion) { return slug }
            print("That is not owner/name. Type it like acme/api.")
        }
        return nil
    }

    /// The repo of the current folder, as gh reads its remote. nil when gh fails or the answer is not owner/name.
    private static func currentFolderRepo() -> String? {
        let r = Shell.run("gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
                          cwd: FileManager.default.currentDirectoryPath, env: ProcessInfo.processInfo.environment, timeout: 30)
        let slug = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && RepoConfig.isValidSlug(slug) ? slug : nil
    }

    /// `init --refresh`, run by `glidepath update` from the new binary after a brew upgrade. Non-interactive: the
    /// skill, the app link and the job are brought in line with this binary. Config, state and pause are left alone.
    /// `holdingLock` is set by `update`, which holds the run lock through the upgrade, so the job is still rewritten.
    static func refresh(holdingLock: Bool = false) -> Int32 {
        let paths = Paths()
        let binary = stableBinary(runningBinary: binaryPath())
        guard let skill = findInstalledDir(relative: "share/glidepath", fallback: "skill/glidepath",
                                           requiredFile: "SKILL.md", from: binary) else {
            eprint("skill files not found next to \(binary)")
            return 1
        }
        do {
            try installSkill(from: skill, to: paths.skillDir)
            print("Installed skill to \(paths.skillDir)")
        } catch {
            eprint("could not install skill: \(error)")
            return 1
        }
        if let app = findApp(from: binary) {
            do {
                try linkApp(InstallKind.appTarget(binary: binary, app: app), at: paths.appLink)
                print("Linked \(paths.appLink)")
            } catch {
                eprint("could not link the app: \(error.localizedDescription)")
            }
        }

        let config: Config
        do {
            config = try Config.load(paths)
        } catch {
            eprint("skipped the scheduled job: \(error)")
            return 1
        }
        // The job is rewritten (and reloaded) only when its content would change. A sweep in progress keeps its job.
        let path = jobPath(paths: paths)
        if jobIsCurrent(paths: paths, config: config, binary: binary, path: path) {
            print("Scheduled job is current")
        } else if !holdingLock && RunLock.isHeld(paths.lockFile) {
            print("skipped the schedule: a run is in progress")
        } else {
            do {
                try installJob(paths: paths, config: config, binary: binary, path: path)
                print("Rewrote the scheduled job at \(paths.plistFile)")
            } catch {
                eprint("could not install the scheduled job: \(error)")
                return 1
            }
        }
        return 0
    }

    /// The PATH the scheduled job runs with, as `init`, `init --refresh` and the app's schedule save derive it now.
    static func jobPath(paths: Paths) -> String {
        GitNexus.jobPath(base: Runner.jobPath(paths) ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                         home: paths.home)
    }

    /// True when the installed plist is exactly what `config` would write for `binary` and `path`. A plist that cannot be
    /// built is not current.
    static func jobIsCurrent(paths: Paths, config: Config, binary: String, path: String) -> Bool {
        guard let wanted = try? Launchd.data(binary: binary, schedule: config.schedule, days: config.days, path: path,
                                             logFile: paths.logFile) else { return false }
        return wanted == (try? Data(contentsOf: URL(fileURLWithPath: paths.plistFile)))
    }

    /// The path the scheduled job, the app link and the skill are written against. A Homebrew keg path does not survive
    /// an upgrade, so it becomes the `opt` path, which Homebrew repoints on each upgrade. Other installs keep their path.
    static func stableBinary(runningBinary: String) -> String {
        if case .homebrew(let prefix) = InstallKind.of(binary: runningBinary) { return prefix + "/bin/glidepath" }
        return runningBinary
    }

    /// Directory of the binary that is running now, with symlinks resolved.
    static func runningBinaryDirectory() -> String {
        URL(fileURLWithPath: binaryPath()).resolvingSymlinksInPath().deletingLastPathComponent().path
    }

    /// The path launchd should run. Prefers the installed PATH entry (stable across upgrades).
    static func binaryPath() -> String {
        let arg0 = CommandLine.arguments[0]
        if arg0.hasPrefix("/") { return arg0 }
        if arg0.contains("/") { return URL(fileURLWithPath: arg0).standardizedFileURL.path }
        return Shell.find("glidepath") ?? Bundle.main.executablePath ?? arg0
    }

    /// The trimmed answer, "" for an empty line, and nil at end of input.
    private static func prompt(_ text: String) -> String? {
        print(text, terminator: "")
        guard let line = readLine() else { return nil }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Looks for `relative` next to the binary, then walks up from it (the dev build layout).
    static func findInstalledDir(relative: String, fallback: String, requiredFile: String, from binary: String) -> String? {
        let start = URL(fileURLWithPath: binary).resolvingSymlinksInPath().deletingLastPathComponent()
        let fm = FileManager.default
        var dir = start
        for _ in 0..<7 {
            let installed = dir.deletingLastPathComponent().path + "/" + relative
            if fm.fileExists(atPath: installed + "/" + requiredFile) { return installed }
            let dev = dir.path + "/" + fallback
            if fm.fileExists(atPath: dev + "/" + requiredFile) { return dev }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    static func findApp(from binary: String) -> String? {
        let start = URL(fileURLWithPath: binary).resolvingSymlinksInPath().deletingLastPathComponent()
        var dir = start
        for _ in 0..<7 {
            for candidate in [dir.deletingLastPathComponent().path + "/Glidepath.app",
                              dir.path + "/build/Glidepath.app"]
            where FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    static func installSkill(from source: String, to dest: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        for file in ["SKILL.md", "rubric.md"] {
            let target = dest + "/" + file
            try? fm.removeItem(atPath: target)
            try fm.copyItem(atPath: source + "/" + file, toPath: target)
        }
    }

    static func linkApp(_ app: String, at link: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (link as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let _ = try? fm.destinationOfSymbolicLink(atPath: link) {
            try fm.removeItem(atPath: link)
        } else if fm.fileExists(atPath: link) {
            throw StateError("\(link) exists and is not a link; remove it to replace it")
        }
        try fm.createSymbolicLink(atPath: link, withDestinationPath: app)
    }

    static func installJob(paths: Paths, config: Config, binary: String, path: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: paths.agentsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (paths.logFile as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        let data = try Launchd.data(binary: binary, schedule: config.schedule, days: config.days, path: path,
                                         logFile: paths.logFile)
        try data.write(to: URL(fileURLWithPath: paths.plistFile), options: .atomic)
        let uid = getuid()
        _ = Shell.run("launchctl", ["bootout", "gui/\(uid)/\(Launchd.label)"])
        var boot = Shell.run("launchctl", ["bootstrap", "gui/\(uid)", paths.plistFile])
        // Error 5 (I/O error) right after a bootout is a race with launchd. One retry after a second.
        if boot.status == 5 {
            sleep(1)
            boot = Shell.run("launchctl", ["bootstrap", "gui/\(uid)", paths.plistFile])
        }
        guard boot.ok else { throw StateError("launchctl bootstrap failed: \(boot.stderr)") }
    }
}
