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

enum Posting: String, Equatable { case comment, review }
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

    var owner: String { String(slug.split(separator: "/").first ?? "") }
    var name: String { String(slug.split(separator: "/").last ?? "") }
}

/// `~/.config/review-radar/config.toml`. Parsing is pure; paths are expanded against `home`.
struct Config: Equatable {
    static let defaultSchedule = ["07:00", "13:00", "19:00"]

    var schedule: [ScheduleTime]
    var limits: Limits
    var repos: [RepoConfig]

    static func load(_ paths: Paths) throws -> Config {
        guard let text = try? String(contentsOfFile: paths.configFile, encoding: .utf8) else {
            throw ConfigError(message: "no config at \(paths.configFile); run review-radar init")
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
        try checkKeys(doc, allowed: ["schedule", "limits", "repo"], where: "top level")

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
        return Config(schedule: schedule, limits: limits, repos: repos)
    }

    private static func parseRepo(_ t: [String: TOMLValue], home: String) throws -> RepoConfig {
        try checkKeys(t, allowed: ["slug", "clone", "posting", "authors", "rules", "rules_mode", "gitnexus"], where: "[[repo]]")
        guard let slug = try string(t["slug"], key: "slug") else { throw ConfigError(message: "[[repo]] needs slug") }
        guard slug.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            throw ConfigError(message: "slug \"\(slug)\" must look like owner/name")
        }
        let clone = try string(t["clone"], key: "clone")
            ?? home + "/review-radar/clones/" + slug.replacingOccurrences(of: "/", with: "-")
        var repo = RepoConfig(slug: slug, clone: expand(clone, home: home))

        if let p = try string(t["posting"], key: "posting") {
            guard let v = Posting(rawValue: p) else { throw ConfigError(message: "posting must be comment or review") }
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
        if let g = try string(t["gitnexus"], key: "gitnexus") {
            guard let v = GitNexusMode(rawValue: g) else { throw ConfigError(message: "gitnexus must be auto, on or off") }
            repo.gitnexus = v
        }
        return repo
    }

    /// Renders the config in the same subset `parse` reads. Used by `init`.
    func render() -> String {
        var out = "schedule = [" + schedule.map { "\"\($0.text)\"" }.joined(separator: ", ") + "]\n"
        out += "\n[limits]\n"
        out += "max_prs_per_run = \(limits.maxPRsPerRun)\n"
        out += "max_changed_lines = \(limits.maxChangedLines)\n"
        out += "split_over_lines = \(limits.splitOverLines)\n"
        for r in repos {
            out += "\n[[repo]]\n"
            out += "slug = \"\(r.slug)\"\n"
            out += "clone = \"\(r.clone)\"\n"
            out += "posting = \"\(r.posting.rawValue)\"\n"
            switch r.authors {
            case .collaborators: out += "authors = \"collaborators\"\n"
            case .anyone: out += "authors = \"anyone\"\n"
            case .logins(let logins):
                out += "authors = [" + logins.map { "\"\($0)\"" }.joined(separator: ", ") + "]\n"
            }
            if let rules = r.rules {
                out += "rules = \"\(rules)\"\n"
                out += "rules_mode = \"\(r.rulesMode.rawValue)\"\n"
            }
            out += "gitnexus = \"\(r.gitnexus.rawValue)\"\n"
        }
        return out
    }
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

private func positiveInt(_ v: TOMLValue?, key: String) throws -> Int? {
    guard let v else { return nil }
    guard case .int(let n) = v, n > 0 else { throw ConfigError(message: "\(key) must be a positive integer") }
    return n
}
