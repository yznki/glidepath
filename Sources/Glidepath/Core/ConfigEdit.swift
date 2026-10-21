import Foundation

/// Edits to `config.toml` made from the window. Each edit is pure: it validates the field it changes and returns a new
/// `Config`, or throws a `ConfigError` and leaves the caller's value as it was. `save` is the only function that writes.
enum ConfigEditor {
    // MARK: Validation

    /// A GitHub login: 1 to 39 letters, digits or hyphens. Returns the login unchanged.
    static func validateLogin(_ login: String) throws -> String {
        guard login.range(of: #"\A[A-Za-z0-9-]{1,39}\z"#, options: .regularExpression) != nil else {
            throw ConfigError(message: "\"\(login)\" is not a GitHub login: letters, digits and hyphens, up to 39")
        }
        return login
    }

    /// A path relative to the repo: not empty, not absolute, no `..` segment, no control characters.
    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !hasControl(path) else {
            throw ConfigError(message: "\"\(path)\" must be a path relative to the repo")
        }
        guard !segments(path).contains("..") else {
            throw ConfigError(message: "\"\(path)\" must not contain ..")
        }
    }

    /// An absolute path (`~` already expanded), with no `..` segment. Used for clones and rules files.
    static func validateAbsolutePath(_ path: String) throws {
        guard path.hasPrefix("/"), !hasControl(path) else {
            throw ConfigError(message: "\"\(path)\" must be an absolute path or start with ~/")
        }
        guard !segments(path).contains("..") else {
            throw ConfigError(message: "\"\(path)\" must not contain ..")
        }
    }

    /// Checks everything a repo carries, for a repo added from the window.
    static func validateRepo(_ repo: RepoConfig) throws {
        guard RepoConfig.isValidSlug(repo.slug) else {
            throw ConfigError(message: "slug \"\(repo.slug)\" must look like owner/name")
        }
        try validateAbsolutePath(repo.clone)
        if let rules = repo.rules { try validateAbsolutePath(rules) }
        if case .logins(let logins) = repo.authors {
            guard !logins.isEmpty else { throw ConfigError(message: "Keep at least one login, or choose Collaborators or Anyone.") }
            for login in logins { _ = try validateLogin(login) }
        }
        for path in repo.flagPaths { try validateRelativePath(path) }
    }

    // MARK: Edits

    static func setPosting(_ config: Config, slug: String, _ posting: Posting) throws -> Config {
        try edit(config, slug) { $0.posting = posting }
    }

    static func setAuthors(_ config: Config, slug: String, _ authors: AuthorPolicy) throws -> Config {
        try edit(config, slug) { repo in
            if case .logins(let logins) = authors {
                guard !logins.isEmpty else { throw ConfigError(message: "Keep at least one login, or choose Collaborators or Anyone.") }
                for login in logins { _ = try validateLogin(login) }
            }
            repo.authors = authors
        }
    }

    /// Sets the rules file (absolute), or clears it with nil. The mode stays as it was.
    static func setRules(_ config: Config, slug: String, path: String?) throws -> Config {
        try edit(config, slug) { repo in
            if let path { try validateAbsolutePath(path) }
            repo.rules = path
        }
    }

    static func setRulesMode(_ config: Config, slug: String, _ mode: RulesMode) throws -> Config {
        try edit(config, slug) { $0.rulesMode = mode }
    }

    static func setGitNexus(_ config: Config, slug: String, _ mode: GitNexusMode) throws -> Config {
        try edit(config, slug) { $0.gitnexus = mode }
    }

    /// The "Refresh the GitNexus index before each sweep" toggle maps to gitnexus_refresh.
    static func setGitNexusRefresh(_ config: Config, slug: String, _ on: Bool) throws -> Config {
        try edit(config, slug) { $0.gitnexusRefresh = on }
    }

    static func addFlaggedPath(_ config: Config, slug: String, path: String) throws -> Config {
        try validateRelativePath(path)
        return try edit(config, slug) { repo in
            guard !repo.flagPaths.contains(path) else { throw ConfigError(message: "\(path) is already flagged") }
            repo.flagPaths.append(path)
        }
    }

    static func removeFlaggedPath(_ config: Config, slug: String, path: String) throws -> Config {
        try edit(config, slug) { repo in
            guard repo.flagPaths.contains(path) else { throw ConfigError(message: "\(path) is not flagged") }
            repo.flagPaths.removeAll { $0 == path }
        }
    }

    /// The note is trimmed; it must say something and stay on one line.
    static func setFlagNote(_ config: Config, slug: String, note: String) throws -> Config {
        let text = note.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw ConfigError(message: "The flag note must not be empty.") }
        guard !hasControl(text) else { throw ConfigError(message: "The flag note must be one line of text.") }
        return try edit(config, slug) { $0.flagNote = text }
    }

    static func removeRepo(_ config: Config, slug: String) throws -> Config {
        guard config.repos.contains(where: { $0.slug == slug }) else {
            throw ConfigError(message: "\(slug) is not in the config")
        }
        var out = config
        out.repos.removeAll { $0.slug == slug }
        return out
    }

    /// The "Notifications" switch: `notify` at the top level of the config.
    static func setNotify(_ config: Config, _ on: Bool) -> Config {
        var out = config
        out.notify = on
        return out
    }

    /// The "Check for updates automatically" switch: `check_updates` at the top level of the config.
    static func setCheckUpdates(_ config: Config, _ on: Bool) -> Config {
        var out = config
        out.checkUpdates = on
        return out
    }

    static func addRepo(_ config: Config, _ repo: RepoConfig) throws -> Config {
        try validateRepo(repo)
        guard !config.repos.contains(where: { $0.slug == repo.slug }) else {
            throw ConfigError(message: "\(repo.slug) is already in the config")
        }
        var out = config
        out.repos.append(repo)
        return out
    }

    // MARK: Defaults

    /// The clone folder a new repo gets, as `Config.parse` names it when `clone` is missing.
    static func defaultClone(slug: String, home: String) -> String {
        home + "/glidepath/clones/" + slug.replacingOccurrences(of: "/", with: "-")
    }

    /// The rules file a repo gets from the Edit button: `<config dir>/rules/owner-name.md`.
    static func defaultRulesPath(slug: String, paths: Paths) -> String {
        paths.configDir + "/rules/" + slug.replacingOccurrences(of: "/", with: "-") + ".md"
    }

    // MARK: Saving

    /// Writes the config atomically: a temp file in the same folder, then a rename over the old file. The mode of an
    /// existing file is kept. The text is parsed back first, so the app never writes a file it cannot read.
    static func save(_ config: Config, paths: Paths) throws {
        let text = config.render()
        _ = try Config.parse(text, home: paths.home)

        let target = paths.configFile
        let dir = (target as NSString).deletingLastPathComponent
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let mode = (try? fm.attributesOfItem(atPath: target)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644

        let temp = dir + "/.config.toml.\(UUID().uuidString).tmp"
        guard fm.createFile(atPath: temp, contents: Data(text.utf8), attributes: [.posixPermissions: mode]) else {
            throw ConfigError(message: "could not write \(temp)")
        }
        guard rename(temp, target) == 0 else {
            let reason = String(cString: strerror(errno))
            try? fm.removeItem(atPath: temp)
            throw ConfigError(message: "could not save config: \(reason)")
        }
    }

    /// Copies an existing config.toml aside before onboarding replaces it, as config.toml.bak-YYYYMMDD-HHMMSS
    /// (a counter is added if that name is taken). Returns the backup path, or nil when there was no file.
    static func backupExisting(paths: Paths, now: Date = Date()) throws -> String? {
        let fm = FileManager.default
        let target = paths.configFile
        guard fm.fileExists(atPath: target) else { return nil }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let base = target + ".bak-" + stamp.string(from: now)
        var backup = base
        var n = 2
        while fm.fileExists(atPath: backup) {
            backup = "\(base)-\(n)"
            n += 1
        }
        try fm.copyItem(atPath: target, toPath: backup)
        return backup
    }

    // MARK: Helpers

    /// Runs `change` on the repo with this slug and returns the config with it replaced.
    private static func edit(_ config: Config, _ slug: String, _ change: (inout RepoConfig) throws -> Void) throws -> Config {
        guard let index = config.repos.firstIndex(where: { $0.slug == slug }) else {
            throw ConfigError(message: "\(slug) is not in the config")
        }
        var repo = config.repos[index]
        try change(&repo)
        var out = config
        out.repos[index] = repo
        return out
    }

    private static func segments(_ path: String) -> [Substring] {
        path.split(separator: "/", omittingEmptySubsequences: false)
    }

    private static func hasControl(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
