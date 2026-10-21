import Foundation

/// Fixtures for the window screens and the onboarding steps, used only by snapshot rendering. Repos are lumen/api and
/// lumen/web, and the rows follow the v1.2 mockups in docs/design/v1.2/, so a render can be set against its mockup.
/// Nothing here reads or writes disk: the stores these feed are `Store(snapshot:)` stores.
enum WindowFixtures {
    static let repos = ["lumen/api", "lumen/web"]
    static let head = "a3f09c1"
    /// The sweep times and days the Schedule and onboarding mockups show.
    static let times = ["07:00", "13:00", "19:00"].compactMap(ScheduleTime.init)

    /// The clock every window render reads: Wednesday 21 Oct at 4:19 PM, so the next sweep is 7:00 PM, 2 h 41 min out.
    static let clock: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 16, minute: 19))
        ?? Date(timeIntervalSince1970: 0)

    static func at(_ h: Int, _ m: Int, _ now: Date) -> Date { Fixtures.clockToday(h, m, now) }

    /// One PR row. `draft` is a held review; `skip` is "size" for a PR too large to review.
    static func row(_ repo: String, _ n: Int, _ author: String, _ title: String, verdict: Verdict?, reason: String? = nil,
                    draft: Bool = false, flagged: Bool = false, skip: String? = nil, lines: Int? = nil,
                    stage: Stage = .post, active: Bool = false, posted: Date? = nil,
                    tokens: Int = 0) -> (String, PRState) {
        var pr = PRState(n: n, author: author, title: title, stage: stage, active: active && verdict == nil,
                         verdict: verdict, reason: reason, tokens: tokens)
        pr.head = head
        pr.posted = posted
        if draft { pr.draft = true }
        if flagged { pr.flagged = true }
        pr.skipReason = skip
        pr.changedLines = lines
        return (repo, pr)
    }

    static func run(_ id: String, _ start: Date, minutes: Double?, prs: [(String, PRState)], tokens: Int) -> RunState {
        RunState(id: id, started: start, finished: minutes.map { start.addingTimeInterval($0 * 60) },
                 repos: repos.map { slug in RepoState(slug: slug, prs: prs.filter { $0.0 == slug }.map(\.1), error: nil) },
                 tokens: tokens, error: nil)
    }

    /// The 1:00 PM sweep: the Overview's "Waiting on you" and "Last sweep", and the Reviews list.
    static func sweepAfternoon(_ now: Date) -> RunState {
        run("fixture-1pm", at(13, 0, now), minutes: 9, prs: [
            row("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", verdict: .changes,
                reason: "missing RLS test", draft: true, flagged: true, tokens: 61_000),
            row("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve, draft: true),
            row("lumen/web", 1219, "tom", "Rewrite the invoice ledger as append-only", verdict: .skipped,
                reason: "too large (12480 changed lines)", skip: "size", lines: 12_480),
            row("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", verdict: .changes,
                reason: "dates shift by a day"),
            row("lumen/api", 1231, "lea", "Add retry to the webhook sender", verdict: .changes,
                reason: "retries are not idempotent"),
            row("lumen/web", 91, "kai", "Redesign the empty states for projects", verdict: .approve),
            row("lumen/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: .approve,
                posted: at(13, 4, now)),
        ], tokens: 412_000)
    }

    /// The 7:00 AM sweep, for the Reviews list's second group.
    static func sweepMorning(_ now: Date) -> RunState {
        run("fixture-7am", at(7, 0, now), minutes: 6, prs: [
            row("lumen/web", 84, "sam", "Bump next to 15.1", verdict: .skipped, reason: "bot"),
        ], tokens: 198_000)
    }

    /// The sweep in progress at 1:00 PM: three PRs in flight, four landed.
    static func sweepRunning(_ now: Date) -> RunState {
        run("fixture-now", at(13, 0, now), minutes: nil, prs: [
            row("lumen/api", 1231, "lea", "Add retry to the webhook sender", verdict: nil, stage: .check, active: true),
            row("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", verdict: nil,
                stage: .review, active: true),
            row("lumen/web", 94, "sam", "Move invoices to the new storage bucket", verdict: nil, stage: .gather, active: true),
            row("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            row("lumen/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: .approve),
            row("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", verdict: .changes,
                reason: "dates shift by a day"),
            row("lumen/web", 91, "kai", "Redesign the empty states for projects", verdict: .approve),
        ], tokens: 188_000)
    }

    /// Review text for the Reviews detail, keyed as `ReviewText` is read: "runId|repo#n".
    static func reviewTexts(_ now: Date) -> [String: ReviewTextRecord] {
        let posted = ISO8601DateFormatter().string(from: at(13, 4, now))
        let cacheBody = """
        Two things to fix before this lands.

        The rate limit is checked after the cache lookup, so a cached response skips it. Move the check above the lookup.

        The new query has no test for a caller from another org, which is the case the cache must never leak.
        """
        return [
            "fixture-1pm|lumen/api#1212": ReviewTextRecord(
                event: "REQUEST_CHANGES", body: cacheBody,
                comments: [
                    PayloadComment(path: "internal/audit/cache.go", line: 42, side: "RIGHT",
                                   body: "The lookup runs before the limit check; a cached hit returns at line 47 without counting."),
                    PayloadComment(path: "internal/audit/cache_test.go", line: 118, side: "RIGHT",
                                   body: "Add a case where a caller from org B reads org A's cached entry; it should miss."),
                ],
                head: head, posted: nil),
            "fixture-1pm|lumen/api#1229": ReviewTextRecord(
                event: "APPROVE", body: "The driver bump is contained. No query text or connection settings changed.",
                comments: [], head: head, posted: nil),
            "fixture-1pm|lumen/web#88": ReviewTextRecord(
                event: "REQUEST_CHANGES", body: "The CSV export formats the picked date in UTC. Format it in the user's zone.",
                comments: [PayloadComment(path: "src/export/csv.ts", line: 27, side: "RIGHT",
                                          body: "toISOString() drops the local offset here.")],
                head: head, posted: posted),
            "fixture-1pm|lumen/api#1231": ReviewTextRecord(
                event: "REQUEST_CHANGES", body: "The retry runs on every delivery, so a slow partner gets the same event twice.",
                comments: [], head: head, posted: posted),
        ]
    }

    /// The repos as the Repos mockup shows them: lumen/api on Full review (flagged paths), lumen/web on Draft first.
    static func config() -> Config {
        var limits = Limits()
        limits.maxChangedLines = 8000
        var config = Config(schedule: times, limits: limits, repos: [])
        config.days = .weekdays
        var api = RepoConfig(slug: "lumen/api", clone: "/Users/you/code/lumen/api")
        api.posting = .review
        api.flagPaths = ["infra/", ".github/workflows/"]
        api.flagNote = "Needs a devops code-owner approval."
        var web = RepoConfig(slug: "lumen/web", clone: "/Users/you/code/lumen/web")
        web.posting = .draft
        config.repos = [api, web]
        return config
    }

    /// The tool checks as Settings and the tools step show them: GitNexus is the one missing, and it is optional.
    static let checks: [Checks.Item] = [
        Checks.Item(name: "Xcode Command Line Tools", ok: true, fix: "xcode-select --install"),
        Checks.Item(name: "git", ok: true, fix: "xcode-select --install"),
        Checks.Item(name: "gh (GitHub CLI)", ok: true, fix: "brew install gh"),
        Checks.Item(name: "gh signed in", ok: true, fix: "gh auth login"),
        Checks.Item(name: "claude (Claude Code)", ok: true, fix: "brew install --cask claude-code"),
        Checks.Item(name: "GitNexus (optional)", ok: false, fix: "npm install -g gitnexus"),
    ]

    /// The snapshot for every window section. Overview shows the 1:00 PM sweep; Running shows one in flight.
    static func section(_ name: String, now: Date) -> Snapshot {
        let runs = [sweepAfternoon(now), sweepMorning(now)]
        // The next sweep comes from the same function the app uses, so the footer and the Schedule subtitle agree.
        var snap = Snapshot(run: runs[0], jobInstalled: true,
                            nextRun: ScheduleTimes.nextSweep(after: now, times: times, days: .weekdays),
                            schedule: times)
        snap.now = now
        snap.config = config()
        snap.repoCount = repos.count
        snap.maxChangedLines = 8000
        snap.runs = runs
        snap.reviewTexts = reviewTexts(now)
        snap.tools = checks
        snap.loginOn = true
        if name == "running" {
            snap.run = sweepRunning(now)
            snap.running = true
        }
        return snap
    }

    /// The onboarding model for one step. `repos` and the tool rows are what the step's checks would have found.
    @MainActor static func onboarding(_ step: OnboardingStep, now: Date, paths: Paths) -> OnboardingModel {
        var state = OnboardingState()
        state.step = step
        state.schedule = times
        state.days = .weekdays
        let discovered = [
            DiscoveredRepo(slug: "lumen/api", language: "Go", pushedAt: now.addingTimeInterval(-720), openPRs: 14),
            DiscoveredRepo(slug: "lumen/web", language: "TypeScript", pushedAt: now.addingTimeInterval(-3600), openPRs: 9),
            DiscoveredRepo(slug: "lumen/infra", language: "HCL", pushedAt: now.addingTimeInterval(-86_400), openPRs: 2),
            DiscoveredRepo(slug: "yznki/dotfiles", language: "Shell", pushedAt: now.addingTimeInterval(-7 * 86_400), openPRs: 0),
        ]
        let tools = [
            ToolRow(id: "claude", title: "Claude Code", meta: "2.4.1 · signed in", ok: true, fix: nil),
            ToolRow(id: "gh", title: "GitHub CLI", meta: "gh 2.62 · signed in as yznki", ok: true, fix: nil),
            ToolRow(id: "git", title: "Git and the Command Line Tools", meta: "git 2.47", ok: true, fix: nil),
            ToolRow(id: "gitnexus", title: "GitNexus (optional)", meta: "Shows reviewers who calls the changed code.",
                    ok: false, fix: "npm install -g gitnexus"),
        ]
        state.tools = ToolStatus(claudeSignedIn: true, ghSignedIn: true, gitReady: true, gitNexus: false)
        state.repos = ["lumen/api", "lumen/web"]
        var strips: [Strip] = []
        if step == .firstSweep {
            state.repos = ["lumen/api"]
            let dry = run("fixture-dry", now, minutes: 4, prs: [
                row("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
                row("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", verdict: .changes,
                    reason: "missing RLS test"),
                row("lumen/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: .approve),
                row("lumen/api", 1231, "lea", "Add retry to the webhook sender", verdict: .changes,
                    reason: "retries are not idempotent"),
            ], tokens: 120_000)
            strips = Store.strips(from: dry)
            let landing = OnboardingSummary.landing(strips, posting: .comment, repo: "lumen/api")
            state.firstSweep = .finished(reviews: landing.reviews, summary: landing.text)
        }
        return OnboardingModel(fixture: state, paths: paths, tools: tools, repos: discovered,
                               repoList: .loaded, liveStrips: strips)
    }
}
