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

/// Weekday in the order a week reads (Monday first). `launchd` is the number launchd's StartCalendarInterval uses,
/// where Sunday is 0.
enum Weekday: Int, CaseIterable, Equatable {
    case mon, tue, wed, thu, fri, sat, sun

    var launchd: Int { (rawValue + 1) % 7 }
    var name: String { "\(self)" }
}

/// Which days the sweeps run on. `all` is the default, so configs written before `days` existed keep their behaviour.
enum ScheduleDays: Equatable {
    case weekdays, all, custom(Set<Weekday>)

    /// The days a sweep runs on, Monday first.
    var active: [Weekday] {
        switch self {
        case .weekdays: return Array(Weekday.allCases.prefix(5))
        case .all: return Weekday.allCases
        case .custom(let set): return Weekday.allCases.filter(set.contains)
        }
    }

    /// The value as `days` is written in config.toml.
    var tomlText: String {
        switch self {
        case .weekdays: return "\"weekdays\""
        case .all: return "\"all\""
        case .custom: return "[" + active.map { tomlQuoted($0.name) }.joined(separator: ", ") + "]"
        }
    }
}

/// The next sweep. The sidebar footer, the Schedule subtitle, the popover and the dashboard all ask this one function.
enum ScheduleTimes {
    /// The first sweep time strictly after `now`, on one of `days`. The times are sorted here. The calendar decides
    /// the day boundaries, so DST is handled by it. Looks eight days ahead, the longest gap a single day allows.
    static func nextSweep(after now: Date, times: [ScheduleTime], days: ScheduleDays = .all,
                          calendar: Calendar = .current) -> Date? {
        let sorted = times.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        let launchdDays = Set(days.active.map(\.launchd))
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            // Calendar's weekday runs Sunday = 1; launchd's runs Sunday = 0.
            guard launchdDays.contains(calendar.component(.weekday, from: day) - 1) else { continue }
            for t in sorted {
                if let candidate = calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day),
                   candidate > now {
                    return candidate
                }
            }
        }
        return nil
    }
}

struct Limits: Equatable {
    var maxPRsPerRun = 10
    var maxChangedLines = 3000
    var splitOverLines = 1500
    /// Keys this version does not know, kept as they were read so a save does not drop them.
    var extras: [String: TOMLValue] = [:]
}

/// `draft` runs the whole pipeline and holds the review for the user to post from the app or `glidepath drafts`.
enum Posting: String, Equatable { case comment, review, draft }
enum AuthorPolicy: Equatable { case collaborators, anyone, logins([String]) }
enum RulesMode: String, Equatable { case extend, replace }
enum GitNexusMode: String, Equatable { case auto, on, off }
/// The model the review sessions run on. Opus is the default, as it was before the key existed.
enum ReviewModel: String, CaseIterable, Equatable { case haiku, sonnet, opus }

/// How hard the review prompt pushes. Balanced adds nothing to the prompt, as it did before the key existed.
enum Strictness: String, CaseIterable, Equatable {
    case relaxed, easygoing, balanced, exacting, ruthless

    /// The sentence appended to the review prompt. Empty for balanced.
    var promptLine: String {
        switch self {
        case .relaxed: return "Let style and small things go; flag only real bugs."
        case .easygoing: return "Flag only what could break."
        case .balanced: return ""
        case .exacting: return "Also flag naming, missing tests and unhandled edge cases."
        case .ruthless: return "Flag every issue you find, including nits."
        }
    }
}

/// The sound a sweep notification plays. `none` plays nothing.
enum NotifySound: String, CaseIterable, Equatable { case none, glass, pop, tink, hero }

/// The `hotkey` key: a bool (true is ⌥⌘G, false is off) or a shortcut such as "⌥⌘G".
enum HotkeySetting: Equatable {
    case off, on, custom(String)

    var isOn: Bool { self != .off }
}

/// What a fix does once its PR is approved. `always` pushes it; `until_approved` (the default) holds it for the user.
enum TendPush: String, CaseIterable, Equatable { case always, untilApproved = "until_approved" }

/// The second-opinion model for stuck fixes. `off` (the default) leaves it out.
enum TendAdvisor: String, CaseIterable, Equatable { case opus, off }

/// The `[tend]` table: Glidepath fixing the user's own PRs. A config without the table keeps tending off.
struct TendConfig: Equatable {
    var enabled = false
    var push: TendPush = .untilApproved
    /// Fix rounds a day, across all PRs.
    var roundsPerDay = 5
    /// Fix attempts on one head before its PR is stuck.
    var triesPerHead = 2
    /// Changed lines one fix may touch. 0 means no cap.
    var maxFixLines = 400
    var autopilot = false
    var advisor: TendAdvisor = .off
    /// Dollars one fix session may spend. Whole dollars: the TOML reader has no floats.
    var maxUsdPerSession = 2
    /// Second-opinion reviews a day. 0 means none.
    var councilPerDay = 10
    /// Hosts a fix session may reach. A `*.` prefix is a wildcard.
    var registries = ["registry.npmjs.org", "pypi.org", "files.pythonhosted.org"]
    /// Percent of the Claude usage window kept back for the user. 0 to 90.
    var usageReserve = 40
    var quietHours = QuietHours.parse("22:00-07:00,sat,sun")!
    /// Keys this version does not know, kept as they were read so a save does not drop them.
    var extras: [String: TOMLValue] = [:]
}

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
    /// Review draft PRs. nil inherits the top-level `review_drafts`.
    var reviewDrafts: Bool?
    /// Refresh the GitNexus index in the clone before a sweep that reviews something. Only when GitNexus is on.
    var gitnexusRefresh = true
    /// Path prefixes that need an extra approval. A PR touching one gets a note on its review.
    var flagPaths: [String] = []
    var flagNote = RepoConfig.defaultFlagNote
    /// Glidepath fixes this repo's own PRs. Off unless the repo asks for it.
    var tend = false
    /// Keys this version does not know, kept as they were read so a save does not drop them.
    var extras: [String: TOMLValue] = [:]

    static let defaultFlagNote = "Touches flagged paths; needs an extra approval."

    static func isValidSlug(_ slug: String) -> Bool {
        guard slug.range(of: #"\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z"#, options: .regularExpression) != nil else { return false }
        // "." and ".." are legal characters but would point the clone path at the clones folder itself or above it.
        return !slug.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }

    var owner: String { String(slug.split(separator: "/").first ?? "") }
    var name: String { String(slug.split(separator: "/").last ?? "") }
}

/// `~/.config/glidepath/config.toml`. Parsing is pure; paths are expanded against `home`.
struct Config: Equatable {
    static let defaultSchedule = ["08:00", "12:00", "16:00", "20:00"]

    /// The config a new setup writes (onboarding and `init` when no config exists): Sonnet and five PRs a sweep.
    /// Parsing a config without these keys still means Opus and ten, so existing configs do not change.
    static func newSetup(schedule: [ScheduleTime], repos: [RepoConfig]) -> Config {
        var config = Config(schedule: schedule, limits: Limits(maxPRsPerRun: 5), repos: repos)
        config.model = .sonnet
        return config
    }

    var schedule: [ScheduleTime]
    var limits: Limits
    var repos: [RepoConfig]
    /// Automatic update checks. Off disables them; "Check for updates…" and `glidepath update` still work.
    var checkUpdates = true
    /// Notification when a sweep finishes. The menu bar app reads it; nothing writes it.
    var notify = true
    var days: ScheduleDays = .all
    /// The global ⌥⌘G shortcut that opens the menu bar popover from any app. Settings writes it; a config without it
    /// keeps the shortcut on.
    var hotkey: HotkeySetting = .on
    /// Review draft PRs, unless a repo says otherwise.
    var reviewDrafts = false
    /// Review PRs from bot accounts too. A bot listed by name in `authors` is reviewed either way.
    var includeBots = false
    var model: ReviewModel = .opus
    var strictness: Strictness = .balanced
    /// Notify only when a sweep has a PR that needs changes.
    var notifyChangesOnly = false
    var notifySound: NotifySound = .glass
    /// False marks the notification time-sensitive, so it can break through a Focus.
    var respectFocus = true
    /// Tokens the scheduled sweeps may use in a calendar month. 0 means no budget.
    var monthlyTokens = 0
    /// Scheduled sweeps stop at the budget. Manual runs ignore it.
    var pauseAtBudget = true
    /// Runs review but post nothing, as `glidepath run --dry-run` does.
    var dryRun = false
    /// The Claude config folder the fix sessions sign in with. nil uses the user's own sign-in.
    var claudeConfigDir: String?
    var tend = TendConfig()
    /// Keys this version does not know, kept as they were read so a save does not drop them.
    var extras: [String: TOMLValue] = [:]

    /// The unknown keys, as notes for `doctor`: top level, then [limits], then each repo.
    var unknownKeys: [String] {
        extras.keys.sorted().map { "\($0) (top level)" }
            + limits.extras.keys.sorted().map { "\($0) in [limits]" }
            + repos.flatMap { repo in repo.extras.keys.sorted().map { "\($0) in repo \(repo.slug)" } }
    }

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
        let topLevelKeys: Set<String> = ["schedule", "days", "limits", "repo", "check_updates", "notify", "hotkey",
                                         "review_drafts", "include_bots", "model", "strictness", "notify_changes_only",
                                         "notify_sound", "respect_focus", "monthly_tokens", "pause_at_budget", "dry_run",
                                         "claude_config_dir", "tend"]

        let scheduleText = try strings(doc["schedule"], key: "schedule") ?? defaultSchedule
        guard !scheduleText.isEmpty else { throw ConfigError(message: "schedule must list at least one time") }
        let schedule = try scheduleText.map { text -> ScheduleTime in
            guard let t = ScheduleTime(text) else { throw ConfigError(message: "schedule: \"\(text)\" is not HH:MM") }
            return t
        }

        let days = try scheduleDays(doc["days"])

        var limits = Limits()
        if let value = doc["limits"] {
            guard case .table(let t) = value else { throw ConfigError(message: "[limits] must be a table") }
            limits.maxPRsPerRun = try positiveInt(t["max_prs_per_run"], key: "max_prs_per_run") ?? limits.maxPRsPerRun
            limits.maxChangedLines = try positiveInt(t["max_changed_lines"], key: "max_changed_lines") ?? limits.maxChangedLines
            limits.splitOverLines = try positiveInt(t["split_over_lines"], key: "split_over_lines") ?? limits.splitOverLines
            limits.extras = extraKeys(t, allowed: ["max_prs_per_run", "max_changed_lines", "split_over_lines"])
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
        let hotkey = try hotkeySetting(doc["hotkey"])
        let monthlyTokens = try nonNegativeInt(doc["monthly_tokens"], key: "monthly_tokens") ?? 0
        var tend = TendConfig()
        if let value = doc["tend"] {
            guard case .table(let t) = value else { throw ConfigError(message: "[tend] must be a table") }
            tend = try parseTend(t)
        }
        return Config(schedule: schedule, limits: limits, repos: repos, checkUpdates: checkUpdates, notify: notify,
                      days: days, hotkey: hotkey,
                      reviewDrafts: try bool(doc["review_drafts"], key: "review_drafts") ?? false,
                      includeBots: try bool(doc["include_bots"], key: "include_bots") ?? false,
                      model: try choice(doc["model"], key: "model") ?? .opus,
                      strictness: try choice(doc["strictness"], key: "strictness") ?? .balanced,
                      notifyChangesOnly: try bool(doc["notify_changes_only"], key: "notify_changes_only") ?? false,
                      notifySound: try choice(doc["notify_sound"], key: "notify_sound") ?? .glass,
                      respectFocus: try bool(doc["respect_focus"], key: "respect_focus") ?? true,
                      monthlyTokens: monthlyTokens,
                      pauseAtBudget: try bool(doc["pause_at_budget"], key: "pause_at_budget") ?? true,
                      dryRun: try bool(doc["dry_run"], key: "dry_run") ?? false,
                      claudeConfigDir: try claudeConfigDir(doc["claude_config_dir"], home: home),
                      tend: tend,
                      extras: extraKeys(doc, allowed: topLevelKeys))
    }

    /// `claude_config_dir`: an absolute path, or one that starts with ~/.
    private static func claudeConfigDir(_ v: TOMLValue?, home: String) throws -> String? {
        guard let text = try string(v, key: "claude_config_dir") else { return nil }
        let path = expand(text, home: home)
        guard path.hasPrefix("/") else {
            throw ConfigError(message: "claude_config_dir \"\(text)\" must be an absolute path or start with ~/")
        }
        return path
    }

    /// The `[tend]` table. Every key is optional; a missing one keeps its default.
    private static func parseTend(_ t: [String: TOMLValue]) throws -> TendConfig {
        var tend = TendConfig()
        tend.enabled = try bool(t["enabled"], key: "enabled") ?? tend.enabled
        tend.push = try choice(t["push"], key: "push") ?? tend.push
        tend.roundsPerDay = try positiveInt(t["rounds_per_day"], key: "rounds_per_day") ?? tend.roundsPerDay
        tend.triesPerHead = try positiveInt(t["tries_per_head"], key: "tries_per_head") ?? tend.triesPerHead
        tend.maxFixLines = try nonNegativeInt(t["max_fix_lines"], key: "max_fix_lines") ?? tend.maxFixLines
        tend.autopilot = try bool(t["autopilot"], key: "autopilot") ?? tend.autopilot
        tend.advisor = try choice(t["advisor"], key: "advisor") ?? tend.advisor
        tend.maxUsdPerSession = try positiveInt(t["max_usd_per_session"], key: "max_usd_per_session") ?? tend.maxUsdPerSession
        tend.councilPerDay = try nonNegativeInt(t["council_per_day"], key: "council_per_day") ?? tend.councilPerDay
        tend.registries = try strings(t["registries"], key: "registries") ?? tend.registries
        if let value = t["usage_reserve"] {
            guard case .int(let n) = value, (0...90).contains(n) else {
                throw ConfigError(message: "usage_reserve must be a whole number from 0 to 90")
            }
            tend.usageReserve = n
        }
        if let text = try string(t["quiet_hours"], key: "quiet_hours") {
            guard let quiet = QuietHours.parse(text) else {
                throw ConfigError(message: "quiet_hours \"\(text)\" must look like 22:00-07:00,sat,sun")
            }
            tend.quietHours = quiet
        }
        tend.extras = extraKeys(t, allowed: ["enabled", "push", "rounds_per_day", "tries_per_head", "max_fix_lines",
                                             "autopilot", "advisor", "max_usd_per_session", "council_per_day",
                                             "registries", "usage_reserve", "quiet_hours"])
        return tend
    }

    /// `hotkey`: true (⌥⌘G), false (off), or a shortcut string that `HotkeySpec` can read.
    private static func hotkeySetting(_ v: TOMLValue?) throws -> HotkeySetting {
        guard let v else { return .on }
        switch v {
        case .bool(let b): return b ? .on : .off
        case .string(let s):
            guard HotkeySpec.parse(s) != nil else {
                throw ConfigError(message: "hotkey \"\(s)\" must be modifiers and a key, such as \"⌥⌘G\"")
            }
            return .custom(s)
        default: throw ConfigError(message: "hotkey must be true, false or a shortcut such as \"⌥⌘G\"")
        }
    }

    /// `days`: "weekdays", "all" (the default when absent) or a list of mon..sun.
    private static func scheduleDays(_ v: TOMLValue?) throws -> ScheduleDays {
        guard let v else { return .all }
        if case .string(let s) = v {
            switch s {
            case "all": return .all
            case "weekdays": return .weekdays
            default: throw ConfigError(message: "days must be \"weekdays\", \"all\" or a list of mon, tue, wed, thu, fri, sat, sun")
            }
        }
        guard let names = try strings(v, key: "days"), !names.isEmpty else {
            throw ConfigError(message: "days must list at least one day")
        }
        var set = Set<Weekday>()
        for name in names {
            guard let day = Weekday.allCases.first(where: { $0.name == name }) else {
                throw ConfigError(message: "days: \"\(name)\" is not mon, tue, wed, thu, fri, sat or sun")
            }
            set.insert(day)
        }
        return .custom(set)
    }

    private static func parseRepo(_ t: [String: TOMLValue], home: String) throws -> RepoConfig {
        guard let slug = try string(t["slug"], key: "slug") else { throw ConfigError(message: "[[repo]] needs slug") }
        guard RepoConfig.isValidSlug(slug) else {
            throw ConfigError(message: "slug \"\(slug)\" must look like owner/name")
        }
        let clone = try string(t["clone"], key: "clone")
            ?? ConfigEditor.defaultClone(slug: slug, home: home)
        let expandedClone = expand(clone, home: home)
        guard expandedClone.hasPrefix("/") else {
            throw ConfigError(message: "clone \"\(clone)\" must be an absolute path or start with ~/")
        }
        var repo = RepoConfig(slug: slug, clone: expandedClone)
        repo.extras = extraKeys(t, allowed: ["slug", "clone", "posting", "authors", "rules", "rules_mode", "gitnexus",
                                             "gitnexus_refresh", "include_own", "review_drafts", "flag_paths", "flag_note",
                                             "tend"])

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
        repo.reviewDrafts = try bool(t["review_drafts"], key: "review_drafts")
        if let paths = try strings(t["flag_paths"], key: "flag_paths") {
            guard paths.allSatisfy({ !$0.isEmpty }) else { throw ConfigError(message: "flag_paths must not contain empty paths") }
            repo.flagPaths = paths
        }
        repo.flagNote = try string(t["flag_note"], key: "flag_note") ?? RepoConfig.defaultFlagNote
        repo.tend = try bool(t["tend"], key: "tend") ?? false
        return repo
    }

    /// Renders the config in the same subset `parse` reads. Used by `init`.
    func render() -> String {
        var out = "schedule = [" + schedule.map { tomlQuoted($0.text) }.joined(separator: ", ") + "]\n"
        out += "check_updates = \(checkUpdates)\n"
        out += "notify = \(notify)\n"
        // Non-default values only: a config with the defaults leaves the keys out, so an older binary still reads it.
        switch hotkey {
        case .on: break
        case .off: out += "hotkey = false\n"
        case .custom(let shortcut): out += "hotkey = \(tomlQuoted(shortcut))\n"
        }
        if days != .all { out += "days = \(days.tomlText)\n" }
        if reviewDrafts { out += "review_drafts = true\n" }
        if includeBots { out += "include_bots = true\n" }
        if model != .opus { out += "model = \(tomlQuoted(model.rawValue))\n" }
        if strictness != .balanced { out += "strictness = \(tomlQuoted(strictness.rawValue))\n" }
        if notifyChangesOnly { out += "notify_changes_only = true\n" }
        if notifySound != .glass { out += "notify_sound = \(tomlQuoted(notifySound.rawValue))\n" }
        if !respectFocus { out += "respect_focus = false\n" }
        if monthlyTokens != 0 { out += "monthly_tokens = \(monthlyTokens)\n" }
        if !pauseAtBudget { out += "pause_at_budget = false\n" }
        if dryRun { out += "dry_run = true\n" }
        if let claudeConfigDir { out += "claude_config_dir = \(tomlQuoted(claudeConfigDir))\n" }
        // Unknown keys go back in their section: plain values after the known ones, tables and arrays of tables last.
        out += tomlLines(extras.filter { !isSection($0.value) })
        out += "\n[limits]\n"
        out += "max_prs_per_run = \(limits.maxPRsPerRun)\n"
        out += "max_changed_lines = \(limits.maxChangedLines)\n"
        out += "split_over_lines = \(limits.splitOverLines)\n"
        out += tomlLines(limits.extras)
        if tend != TendConfig() {
            let d = TendConfig()
            out += "\n[tend]\n"
            if tend.enabled != d.enabled { out += "enabled = \(tend.enabled)\n" }
            if tend.push != d.push { out += "push = \(tomlQuoted(tend.push.rawValue))\n" }
            if tend.roundsPerDay != d.roundsPerDay { out += "rounds_per_day = \(tend.roundsPerDay)\n" }
            if tend.triesPerHead != d.triesPerHead { out += "tries_per_head = \(tend.triesPerHead)\n" }
            if tend.maxFixLines != d.maxFixLines { out += "max_fix_lines = \(tend.maxFixLines)\n" }
            if tend.autopilot != d.autopilot { out += "autopilot = \(tend.autopilot)\n" }
            if tend.advisor != d.advisor { out += "advisor = \(tomlQuoted(tend.advisor.rawValue))\n" }
            if tend.maxUsdPerSession != d.maxUsdPerSession { out += "max_usd_per_session = \(tend.maxUsdPerSession)\n" }
            if tend.councilPerDay != d.councilPerDay { out += "council_per_day = \(tend.councilPerDay)\n" }
            if tend.registries != d.registries {
                out += "registries = [" + tend.registries.map { tomlQuoted($0) }.joined(separator: ", ") + "]\n"
            }
            if tend.usageReserve != d.usageReserve { out += "usage_reserve = \(tend.usageReserve)\n" }
            if tend.quietHours != d.quietHours { out += "quiet_hours = \(tomlQuoted(tend.quietHours.text))\n" }
            out += tomlLines(tend.extras)
        }
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
            if let drafts = r.reviewDrafts { out += "review_drafts = \(drafts)\n" }
            if r.tend { out += "tend = true\n" }
            out += "gitnexus_refresh = \(r.gitnexusRefresh)\n"
            if !r.flagPaths.isEmpty {
                out += "flag_paths = [" + r.flagPaths.map { tomlQuoted($0) }.joined(separator: ", ") + "]\n"
            }
            if !r.flagPaths.isEmpty || r.flagNote != RepoConfig.defaultFlagNote {
                out += "flag_note = \(tomlQuoted(r.flagNote))\n"
            }
            out += tomlLines(r.extras)
        }
        for (key, value) in extras.sorted(by: { $0.key < $1.key }) {
            if case .table(let table) = value {
                out += "\n[\(tomlKey(key))]\n" + tomlLines(table)
            } else if case .array(let items) = value, isArrayOfTables(value) {
                for case .table(let table) in items {
                    out += "\n[[\(tomlKey(key))]]\n" + tomlLines(table)
                }
            }
        }
        return out
    }

    private func isSection(_ value: TOMLValue) -> Bool {
        if case .table = value { return true }
        return isArrayOfTables(value)
    }

    private func isArrayOfTables(_ value: TOMLValue) -> Bool {
        guard case .array(let items) = value, !items.isEmpty else { return false }
        return items.allSatisfy { item in
            if case .table = item { return true }
            return false
        }
    }

    /// One `key = value` line per entry, sorted by key.
    private func tomlLines(_ table: [String: TOMLValue]) -> String {
        table.sorted { $0.key < $1.key }.map { "\(tomlKey($0.key)) = \($0.value.tomlText)\n" }.joined()
    }
}

extension TOMLValue {
    /// The value on one line, as TOML writes it. Tables are inline, `{ k = v }`, which `TOML.parse` reads back.
    var tomlText: String {
        switch self {
        case .string(let s): return tomlQuoted(s)
        case .int(let n): return String(n)
        case .bool(let b): return String(b)
        case .array(let items): return "[" + items.map(\.tomlText).joined(separator: ", ") + "]"
        case .table(let table):
            if table.isEmpty { return "{}" }
            return "{ " + table.sorted { $0.key < $1.key }.map { "\(tomlKey($0.key)) = \($0.value.tomlText)" }
                .joined(separator: ", ") + " }"
        }
    }
}

/// A key as TOML writes it: bare when it only has characters a bare key may have, quoted otherwise.
func tomlKey(_ key: String) -> String {
    let bare = !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    return bare ? key : tomlQuoted(key)
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

/// The keys this version does not know. They are kept, not refused, so a file from a newer version still loads.
private func extraKeys(_ t: [String: TOMLValue], allowed: Set<String>) -> [String: TOMLValue] {
    t.filter { !allowed.contains($0.key) }
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

private func nonNegativeInt(_ v: TOMLValue?, key: String) throws -> Int? {
    guard let v else { return nil }
    guard case .int(let n) = v, n >= 0 else { throw ConfigError(message: "\(key) must be a whole number, 0 or more") }
    return n
}

/// A string key whose value is one of the enum's raw values.
private func choice<T: CaseIterable & RawRepresentable>(_ v: TOMLValue?, key: String) throws -> T? where T.RawValue == String {
    guard let v else { return nil }
    guard case .string(let s) = v, let value = T(rawValue: s) else {
        let names = T.allCases.map(\.rawValue).joined(separator: ", ")
        throw ConfigError(message: "\(key) must be one of \(names)")
    }
    return value
}
