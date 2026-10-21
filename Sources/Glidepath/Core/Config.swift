import Foundation

struct ConfigError: Error, CustomStringConvertible, Equatable {
    var message: String
    var description: String { message }
}

struct ScheduleTime: Equatable, Hashable {
    let hour: Int
    let minute: Int

    init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        hour = h
        minute = m
    }

    var text: String { String(format: "%02d:%02d", hour, minute) }
}

struct Limits: Equatable {
    var maxPRsPerRun = 10
    var maxChangedLines = 3000
    var splitOverLines = 1500
}

/// `draft` runs the whole pipeline and holds the review for the user to post from the app or `glidepath drafts`.
enum Posting: String, Equatable { case comment, review, draft }
enum AuthorPolicy: Equatable { case collaborators, anyone, logins([String]) }
enum RulesMode: String, Equatable { case extend, replace }
enum GitNexusMode: String, Equatable { case auto, on, off }

struct RepoConfig: Equatable {
    var slug: String
    var clone: String
    var posting: Posting = .comment
    var authors: AuthorPolicy = .collaborators
    var rules: String?
    var rulesMode: RulesMode = .extend
    var gitnexus: GitNexusMode = .auto
    /// Review the user's own PRs too. Off by default; posting to your own PR is always a COMMENT review.
    var includeOwn = false
    /// Refresh the GitNexus index in the clone before a sweep that reviews something. Only when GitNexus is on.
    var gitnexusRefresh = true
    /// Path prefixes that need an extra approval. A PR touching one gets a note on its review.
    var flagPaths: [String] = []
    var flagNote = RepoConfig.defaultFlagNote

    static let defaultFlagNote = "Touches flagged paths; needs an extra approval."

    static func isValidSlug(_ slug: String) -> Bool {
        slug.range(of: #"\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z"#, options: .regularExpression) != nil
    }

    var owner: String { String(slug.split(separator: "/").first ?? "") }
    var name: String { String(slug.split(separator: "/").last ?? "") }
}

/// `~/.config/glidepath/config.toml`. Parsing is pure; paths are expanded against `home`.
struct Config: Equatable {
    static let defaultSchedule = ["07:00", "13:00", "19:00"]

    var schedule: [ScheduleTime]
    var limits: Limits
    var repos: [RepoConfig]
    /// Automatic update checks. Off disables them; "Check for updates…" and `glidepath update` still work.
    var checkUpdates = true
    /// Notification when a sweep finishes. The menu bar app reads it; nothing writes it.
    var notify = true

    static func load(_ paths: Paths) throws -> Config {
        guard let text = try? String(contentsOfFile: paths.configFile, encoding: .utf8) else {
            throw ConfigError(message: "no config at \(paths.configFile); run glidepath init")
        }
        return try parse(text, home: paths.home)
    }

    static func parse(_ text: String, home: String) throws -> Config {
        let doc: [String: TOMLValue]
        do {
            doc = try TOML.parse(text)
        } catch let e as TOMLError {
            throw ConfigError(message: "config.toml: \(e)")
        }
        try checkKeys(doc, allowed: ["schedule", "limits", "repo", "check_updates", "notify"], where: "top level")

        let scheduleText = try strings(doc["schedule"], key: "schedule") ?? defaultSchedule
        guard !scheduleText.isEmpty else { throw ConfigError(message: "schedule must list at least one time") }
        let schedule = try scheduleText.map { text -> ScheduleTime in
            guard let t = ScheduleTime(text) else { throw ConfigError(message: "schedule: \"\(text)\" is not HH:MM") }
            return t
        }

        var limits = Limits()
        if let value = doc["limits"] {
            guard case .table(let t) = value else { throw ConfigError(message: "[limits] must be a table") }
            try checkKeys(t, allowed: ["max_prs_per_run", "max_changed_lines", "split_over_lines"], where: "[limits]")
            limits.maxPRsPerRun = try positiveInt(t["max_prs_per_run"], key: "max_prs_per_run") ?? limits.maxPRsPerRun
            limits.maxChangedLines = try positiveInt(t["max_changed_lines"], key: "max_changed_lines") ?? limits.maxChangedLines
            limits.splitOverLines = try positiveInt(t["split_over_lines"], key: "split_over_lines") ?? limits.splitOverLines
        }

        var repos: [RepoConfig] = []
        if let value = doc["repo"] {
            guard case .array(let items) = value else { throw ConfigError(message: "[[repo]] must be an array of tables") }
            for item in items {
                guard case .table(let t) = item else { throw ConfigError(message: "[[repo]] must be an array of tables") }
                let repo = try parseRepo(t, home: home)
                guard !repos.contains(where: { $0.slug == repo.slug }) else {
                    throw ConfigError(message: "repo \(repo.slug) is listed twice")
                }
                repos.append(repo)
            }
        }
        let checkUpdates = try bool(doc["check_updates"], key: "check_updates") ?? true
        let notify = try bool(doc["notify"], key: "notify") ?? true
        return Config(schedule: schedule, limits: limits, repos: repos, checkUpdates: checkUpdates, notify: notify)
    }

    private static func parseRepo(_ t: [String: TOMLValue], home: String) throws -> RepoConfig {
        try checkKeys(t, allowed: ["slug", "clone", "posting", "authors", "rules", "rules_mode", "gitnexus", "gitnexus_refresh",
                                   "include_own", "flag_paths", "flag_note"], where: "[[repo]]")
        guard let slug = try string(t["slug"], key: "slug") else { throw ConfigError(message: "[[repo]] needs slug") }
        guard RepoConfig.isValidSlug(slug) else {
            throw ConfigError(message: "slug \"\(slug)\" must look like owner/name")
        }
        let clone = try string(t["clone"], key: "clone")
            ?? home + "/glidepath/clones/" + slug.replacingOccurrences(of: "/", with: "-")
        let expandedClone = expand(clone, home: home)
        guard expandedClone.hasPrefix("/") else {
            throw ConfigError(message: "clone \"\(clone)\" must be an absolute path or start with ~/")
        }
        var repo = RepoConfig(slug: slug, clone: expandedClone)

        if let p = try string(t["posting"], key: "posting") {
            guard let v = Posting(rawValue: p) else { throw ConfigError(message: "posting must be comment, review or draft") }
            repo.posting = v
        }
        if let value = t["authors"] {
            switch value {
            case .string("collaborators"): repo.authors = .collaborators
            case .string("anyone"): repo.authors = .anyone
            case .array:
                let logins = try strings(value, key: "authors") ?? []
                guard !logins.isEmpty else { throw ConfigError(message: "authors list must not be empty") }
                repo.authors = .logins(logins)
            default: throw ConfigError(message: "authors must be \"collaborators\", \"anyone\" or a list of logins")
            }
        }
        if let r = try string(t["rules"], key: "rules") { repo.rules = expand(r, home: home) }
        if let m = try string(t["rules_mode"], key: "rules_mode") {
            guard let v = RulesMode(rawValue: m) else { throw ConfigError(message: "rules_mode must be extend or replace") }
            repo.rulesMode = v
        }
        if let value = t["include_own"] {
            guard case .bool(let b) = value else { throw ConfigError(message: "include_own must be true or false") }
            repo.includeOwn = b
        }
        if let g = try string(t["gitnexus"], key: "gitnexus") {
            guard let v = GitNexusMode(rawValue: g) else { throw ConfigError(message: "gitnexus must be auto, on or off") }
            repo.gitnexus = v
        }
        repo.gitnexusRefresh = try bool(t["gitnexus_refresh"], key: "gitnexus_refresh") ?? true
        if let paths = try strings(t["flag_paths"], key: "flag_paths") {
            guard paths.allSatisfy({ !$0.isEmpty }) else { throw ConfigError(message: "flag_paths must not contain empty paths") }
            repo.flagPaths = paths
        }
        repo.flagNote = try string(t["flag_note"], key: "flag_note") ?? RepoConfig.defaultFlagNote
        return repo
    }

    /// Renders the config in the same subset `parse` reads. Used by `init`.
    func render() -> String {
        var out = "schedule = [" + schedule.map { tomlQuoted($0.text) }.joined(separator: ", ") + "]\n"
        out += "check_updates = \(checkUpdates)\n"
        out += "notify = \(notify)\n"
        out += "\n[limits]\n"
        out += "max_prs_per_run = \(limits.maxPRsPerRun)\n"
        out += "max_changed_lines = \(limits.maxChangedLines)\n"
        out += "split_over_lines = \(limits.splitOverLines)\n"
        for r in repos {
            out += "\n[[repo]]\n"
            out += "slug = \(tomlQuoted(r.slug))\n"
            out += "clone = \(tomlQuoted(r.clone))\n"
            out += "posting = \(tomlQuoted(r.posting.rawValue))\n"
            switch r.authors {
            case .collaborators: out += "authors = \"collaborators\"\n"
            case .anyone: out += "authors = \"anyone\"\n"
            case .logins(let logins):
                out += "authors = [" + logins.map { tomlQuoted($0) }.joined(separator: ", ") + "]\n"
            }
            if let rules = r.rules {
                out += "rules = \(tomlQuoted(rules))\n"
            }
            // Written whenever it differs from the default, so an edit to it reads back without a rules file.
            if r.rules != nil || r.rulesMode != .extend {
                out += "rules_mode = \(tomlQuoted(r.rulesMode.rawValue))\n"
            }
            out += "gitnexus = \(tomlQuoted(r.gitnexus.rawValue))\n"
            out += "include_own = \(r.includeOwn)\n"
            out += "gitnexus_refresh = \(r.gitnexusRefresh)\n"
            if !r.flagPaths.isEmpty {
                out += "flag_paths = [" + r.flagPaths.map { tomlQuoted($0) }.joined(separator: ", ") + "]\n"
            }
            if !r.flagPaths.isEmpty || r.flagNote != RepoConfig.defaultFlagNote {
                out += "flag_note = \(tomlQuoted(r.flagNote))\n"
            }
        }
        return out
    }
}

/// A TOML basic string that reads back as `text`: backslash, quote and the line breaks are escaped. Walks scalars,
/// so a `"` followed by a combining mark is still escaped.
func tomlQuoted(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

// MARK: - Typed readers

private func expand(_ path: String, home: String) -> String {
    path.hasPrefix("~/") ? home + String(path.dropFirst(1)) : path
}

private func checkKeys(_ t: [String: TOMLValue], allowed: Set<String>, where place: String) throws {
    for key in t.keys where !allowed.contains(key) {
        throw ConfigError(message: "unknown key \(key) in \(place)")
    }
}

private func string(_ v: TOMLValue?, key: String) throws -> String? {
    guard let v else { return nil }
    guard case .string(let s) = v else { throw ConfigError(message: "\(key) must be a string") }
    return s
}

private func strings(_ v: TOMLValue?, key: String) throws -> [String]? {
    guard let v else { return nil }
    guard case .array(let items) = v else { throw ConfigError(message: "\(key) must be a list of strings") }
    return try items.map { item in
        guard case .string(let s) = item else { throw ConfigError(message: "\(key) must be a list of strings") }
        return s
    }
}

private func bool(_ v: TOMLValue?, key: String) throws -> Bool? {
    guard let v else { return nil }
    guard case .bool(let b) = v else { throw ConfigError(message: "\(key) must be true or false") }
    return b
}

private func positiveInt(_ v: TOMLValue?, key: String) throws -> Int? {
    guard let v else { return nil }
    guard case .int(let n) = v, n > 0 else { throw ConfigError(message: "\(key) must be a positive integer") }
    return n
}
