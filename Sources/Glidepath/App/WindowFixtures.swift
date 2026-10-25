import Foundation

/// Fixtures for the window screens and the onboarding steps, used only by snapshot rendering. Repos are lumen/api and
/// lumen/web, and the rows follow the v1.2 mockups in docs/design/v1.2/, so a render can be set against its mockup.
/// Nothing here reads or writes disk: the stores these feed are `Store(snapshot:)` stores.
enum WindowFixtures {
    static let repos = ["lumen/api", "lumen/web"]
    static let head = "a3f09c1"
    /// The sweep times and days the Schedule and onboarding mockups show.
    static let times = ["08:00", "12:00", "16:00", "20:00"].compactMap(ScheduleTime.init)

    /// The clock every window render reads: Wednesday 21 Oct at 4:19 PM, so the next sweep is 8:00 PM, 3 h 41 min out.
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

    static func run(_ id: String, _ start: Date, minutes: Double?, prs: [(String, PRState)], tokens: Int,
                    kind: String? = nil, target: String? = nil) -> RunState {
        RunState(id: id, started: start, finished: minutes.map { start.addingTimeInterval($0 * 60) },
                 repos: repos.map { slug in RepoState(slug: slug, prs: prs.filter { $0.0 == slug }.map(\.1), error: nil) },
                 tokens: tokens, error: nil, kind: kind, target: target)
    }

    /// The 1:00 PM sweep: six reviewed (two held), one stopped, one too large. The earlier sweep the author run follows.
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
            row("lumen/api", 1258, "lea", "Fetch an alarm's preview under bounds", verdict: nil, stage: .review),
        ], tokens: 412_000)
    }

    /// The by-hand review of one author's PRs at 3:40 PM, after the 1:00 PM sweep: four reviewed (two held), 21 already
    /// reviewed and skipped, and two rows the review did not touch, carried from the sweep.
    static func authorRun(_ now: Date) -> RunState {
        let carriedFrom = at(13, 0, now)
        func carry(_ entry: (String, PRState)) -> (String, PRState) {
            var pr = entry.1
            pr.carriedFrom = carriedFrom
            return (entry.0, pr)
        }
        let alreadyReviewed = [1285, 1284, 1283, 1282, 1281, 1280, 1279, 1278, 1273, 1272, 1271, 1270, 1269, 1268,
                               1267, 1266, 1265, 1264, 1263, 1262, 1231]
        var prs: [(String, PRState)] = [
            row("lumen/web", 1274, "eleyy", "Read-only endpoints for the asset list", verdict: .approve,
                reason: "a few edge cases worth tightening", posted: at(15, 44, now)),
            row("lumen/web", 1275, "eleyy", "Cross-discipline row adoption", verdict: .changes,
                reason: "legacy lock mismatch", posted: at(15, 46, now)),
            row("lumen/web", 1276, "eleyy", "Selection race in the upload picker", verdict: .changes,
                reason: "race still open; no error state", draft: true),
            row("lumen/web", 1277, "eleyy", "Fan-out publish for shared ids", verdict: .changes,
                reason: "drops a second owner of the same id", draft: true),
        ]
        prs += alreadyReviewed.map { n in
            row("lumen/web", n, "eleyy", "Open PR", verdict: .skipped, reason: "already reviewed at this head")
        }
        prs += [carry(row("lumen/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: .approve)),
                carry(row("lumen/web", 91, "kai", "Redesign the empty states for projects", verdict: .approve))]
        return run("fixture-eleyy", at(15, 40, now), minutes: 14, prs: prs, tokens: 1_700_000,
                   kind: "review", target: "author:eleyy")
    }

    /// The 7:00 AM sweep: two reviewed, one stopped in gather, one bot skipped.
    static func sweepMorning(_ now: Date) -> RunState {
        run("fixture-7am", at(7, 0, now), minutes: 6, prs: [
            row("lumen/api", 1300, "ines", "Index the alarm history by device", verdict: .approve, posted: at(7, 3, now)),
            row("lumen/api", 1125, "sam", "Retry the export on a 429", verdict: .changes,
                reason: "no backoff cap", posted: at(7, 4, now)),
            row("lumen/api", 808, "ana", "ENG-424", verdict: nil, stage: .gather),
            row("lumen/web", 84, "sam", "Bump next to 15.1", verdict: .skipped, reason: "bot author"),
        ], tokens: 198_000)
    }

    /// The sweep in progress at 1:00 PM: three PRs in flight, four landed.
    static func sweepRunning(_ now: Date) -> RunState {
        run("fixture-now", now.addingTimeInterval(-252), minutes: nil, prs: [
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
        let authorPosted = ISO8601DateFormatter().string(from: at(15, 44, now))
        return [
            "fixture-eleyy|lumen/web#1274": ReviewTextRecord(
                event: "APPROVE", body: "The endpoints are read-only and paginate. Two edge cases worth tightening.",
                comments: [], head: head, posted: authorPosted),
            "fixture-eleyy|lumen/web#1275": ReviewTextRecord(
                event: "REQUEST_CHANGES", body: "The row adoption takes the legacy lock but the new path does not.",
                comments: [], head: head, posted: authorPosted),
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

    /// The snapshot for every window section. Now shows the 1:00 PM sweep; Running shows one in flight.
    static func section(_ name: String, now: Date) -> Snapshot {
        let runs = [authorRun(now), sweepAfternoon(now), sweepMorning(now)]
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
        if name == "now-clear" {
            // Nothing held and nothing running: the newest run is the morning sweep.
            snap.run = sweepMorning(now)
            snap.runs = [sweepMorning(now), sweepAfternoon(now)]
        }
        if name == "now-dry-run" {
            // The first sweep's dry run holds the lock. It is not the current run, so the run is nil.
            snap.run = nil
            snap.dryRunning = true
            snap.dryRun = firstSweepRun(now, landed: false)
        }
        return snap
    }

    /// The first sweep's dry run of three PRs: one landed and two in flight while it runs, all three landed when it ends.
    /// Seven PRs are skipped: one yours, three too large, three already reviewed.
    static func firstSweepRun(_ now: Date, landed: Bool) -> RunState {
        let reviewed: [(String, PRState)] = landed ? [
            row("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            row("lumen/api", 1212, "omar", "Cache org permissions per request in the audit log", verdict: .changes,
                reason: "missing RLS test"),
            row("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", verdict: .approve),
        ] : [
            row("lumen/api", 1229, "dana", "Bump Postgres driver to 3.4", verdict: .approve),
            row("lumen/api", 1225, "tom", "Drop the legacy webhook retry table", verdict: nil, stage: .review, active: true),
            row("lumen/web", 88, "lea", "Fix the date picker timezone on CSV export", verdict: nil, stage: .check, active: true),
        ]
        let skipped: [(String, PRState)] = [
            row("lumen/api", 1100, "yznki", "Rotate the staging keys", verdict: .skipped, reason: "your own PR"),
            row("lumen/api", 1101, "omar", "Move billing to the new ledger", verdict: .skipped,
                reason: "too large (4000 changed lines)", skip: "size", lines: 4000),
            row("lumen/api", 1102, "tom", "Split the audit tables", verdict: .skipped,
                reason: "too large (2100 changed lines)", skip: "size", lines: 2100),
            row("lumen/api", 1103, "dana", "Vendor the SDK", verdict: .skipped,
                reason: "too large (2500 changed lines)", skip: "size", lines: 2500),
            row("lumen/web", 90, "sam", "Rewrite the onboarding copy", verdict: .skipped,
                reason: "already reviewed at this head"),
            row("lumen/web", 91, "kai", "Redesign the empty states", verdict: .skipped,
                reason: "already reviewed at this head"),
            row("lumen/web", 92, "ines", "Bump the chart library", verdict: .skipped,
                reason: "already reviewed at this head"),
        ]
        return run("fixture-first-sweep", now, minutes: landed ? 3.2 : nil, prs: reviewed + skipped, tokens: 120_000)
    }

    /// The review sheet, landed: a changes review held as a draft, checked (4 kept, 1 added), with grep-only blast radius.
    /// The copy is the flight recorder prototype's.
    static func reviewLanded() -> (row: ReviewRow, text: ReviewTextRecord, artifacts: RunArtifacts) {
        let body = """
        Went through this at `9c86e39`, skipping what's already open in the threads or fixed by the author. Wiring is real now: the runner only passes the shared fetcher and spool to adapters that set `accepts_evidence`, so the other adapters keep their no-arg constructors.

        Five things inline: no byte cap on the spool, the pin only tries the first approved address, previews share the four process-wide DNS slots with the device paths, the age cap trusts a wall clock that can jump, and the Host header is malformed for IPv6 literals.
        """
        let comments = [
            PayloadComment(path: "evidence.py", line: 482, side: "RIGHT",
                           body: "`MAX_ITEMS = 64` is the only bound on the spool, and each item can be up to 8 MB, so the worst case is about 512 MB on a disk the docstring calls small and shared."),
            PayloadComment(path: "evidence.py", line: 321, side: "RIGHT",
                           body: "`address = approved[0]` pins the whole fetch to the first resolved address, so a dual-stack name whose first answer is unreachable never falls back."),
            PayloadComment(path: "evidence.py", line: 326, side: "RIGHT",
                           body: "`parsed.hostname` strips the brackets from an IPv6 literal, so the Host header goes out as `fd00::1:8080`."),
            PayloadComment(path: "evidence.py", line: 282, side: "RIGHT",
                           body: "Previews share the 4 resolver slots with device paths."),
            PayloadComment(path: "evidence_upload.py", line: 265, side: "RIGHT",
                           body: "Age cap trusts a wall clock that can jump."),
        ]
        let row = ReviewRow(runId: "fixture-landed", repo: "lumen/api", number: 1258, author: "waelananzeh98",
                            title: "ENG-710 M3.4 (2 of 2): fetch an alarm's preview under bounds, spool it, upload it",
                            reason: "Spool disk cap, single-address pin, shared DNS slots", verdict: .changes, draft: true,
                            skipReason: nil, changedLines: 3466, head: "9c86e39", flagged: false, tokens: 427_000,
                            duration: 31 * 60, postedAt: nil, stage: .post)
        let text = ReviewTextRecord(event: "REQUEST_CHANGES", body: body, comments: comments, head: "9c86e39", posted: nil)
        // Two drafts, merged by the checker. Their findings are the four the checker kept; the fifth is its addition.
        let draftA = RunArtifacts.Review(
            verdict: .changes, reason: "Spool disk cap, single-address pin",
            body: body + "\n\nThe bus comment is the same pattern as the spool, so it needs the same cap.",
            comments: [
                RunArtifacts.Comment(path: "evidence_upload.py", line: 265, body: "Age cap trusts a wall clock that can jump."),
                RunArtifacts.Comment(path: "evidence.py", line: 282, body: "Previews share the 4 resolver slots with device paths."),
            ])
        let draftB = RunArtifacts.Review(
            verdict: .changes, reason: nil, body: "",
            comments: [
                RunArtifacts.Comment(path: "evidence.py", line: 482, body: "No byte cap on the spool."),
                RunArtifacts.Comment(path: "evidence.py", line: 321, body: "Fetch pinned to the first approved address."),
            ])
        let final = RunArtifacts.Review(
            verdict: .changes, reason: "Spool disk cap, single-address pin", body: body,
            comments: [
                RunArtifacts.Comment(path: "evidence.py", line: 326, body: comments[2].body),
                RunArtifacts.Comment(path: "evidence.py", line: 482, body: comments[0].body),
                RunArtifacts.Comment(path: "evidence.py", line: 321, body: comments[1].body),
                RunArtifacts.Comment(path: "evidence.py", line: 282, body: comments[3].body),
                RunArtifacts.Comment(path: "evidence_upload.py", line: 265, body: comments[4].body),
            ])
        let blast = """
        Callers from grep, partial. Changed symbols were searched by name.
        - `net.py` is shared network policy. Device paths that call `assert_endpoint_allowed` may be affected.
        - `reconciler.py` changed (+22 −2). Callers in `soak.py` and tests still construct it with defaults.
        - Stacked on #1257. Routes it calls live there, not on main.
        """
        let artifacts = RunArtifacts(
            folder: "/fixture/review-landed", fileCount: 13, additions: 3460, deletions: 6, headSha: "9c86e39f1d2e",
            baseRef: "main", reviewCount: 9, reviewCommentCount: 71, issueCommentCount: 22,
            drafts: [draftA, draftB], final: final, blast: blast,
            notes: ["Feature freeze runs to 2026-11-15; flagged once for whoever merges. Not a blocker.",
                    "Couldn't check the `/pulse/gateway/event-artifacts` routes: they live in #1257."],
            diffParts: 13)
        return (row, text, artifacts)
    }

    /// The review sheet, no result: the run stopped at gather because GitHub refused the diff of a 300-plus-file PR.
    static func reviewNoResult() -> (row: ReviewRow, artifacts: RunArtifacts) {
        let row = ReviewRow(runId: "fixture-noresult", repo: "lumen/api", number: 808, author: "abdeen-1",
                            title: "ENG-424", reason: nil, verdict: nil, draft: false, skipReason: nil,
                            changedLines: 46_265, head: "bb8113d", flagged: false, tokens: 58_000,
                            duration: 2 * 60, postedAt: nil, stage: .gather)
        let artifacts = RunArtifacts(
            folder: "/fixture/review-noresult", fileCount: 100, headSha: "bb8113d9a0c4", reviewCount: 19,
            reviewCommentCount: 36, issueCommentCount: 3,
            blast: "NOT COMPLETE: no diff, so no changed symbols to search for.",
            notes: ["`glidepath pr diff` got HTTP 406: \"diff exceeded the maximum number of files (300)\". GitHub refuses diffs over 300 files, so the diff could not be read.",
                    "No review was posted: a verdict with no diff would be a guess.",
                    "The PR is 46k changed lines. It likely needs splitting before anyone can review it well."])
        return (row, artifacts)
    }

    /// The review sheet, not posted: a changes verdict whose draft was discarded, so no draft and no posting. The
    /// checker's final is absent, so the approach ends at the check and the Land figure says so.
    static func reviewNotPosted() -> (row: ReviewRow, artifacts: RunArtifacts) {
        let row = ReviewRow(runId: "fixture-notposted", repo: "lumen/web", number: 1262, author: "ibrahim-k",
                            title: "Pin the preview cache TTL", reason: "Cache key ignores the tenant", verdict: .changes,
                            draft: false, skipReason: nil, changedLines: 212, head: "4e0a1f2", flagged: false,
                            tokens: 96_000, duration: 6 * 60 + 41, postedAt: nil, stage: .post)
        let draft = RunArtifacts.Review(
            verdict: .changes, reason: "Cache key ignores the tenant", body: "The cache key drops the tenant id, so one tenant can read another's previews.",
            comments: [
                RunArtifacts.Comment(path: "cache.ts", line: 48, body: "The key is built from the path alone, so tenants share entries."),
                RunArtifacts.Comment(path: "preview.ts", line: 91, body: "The TTL is read before the tenant is known."),
            ])
        let artifacts = RunArtifacts(
            folder: "/fixture/review-notposted", fileCount: 9, additions: 201, deletions: 11, headSha: "4e0a1f2c9b7d",
            baseRef: "main", reviewCount: 2, reviewCommentCount: 4, issueCommentCount: 1,
            drafts: [draft],
            blast: "Callers from GitNexus, 4 found.\n- `cache.ts` is read by `preview.ts` and `tenant.ts`.",
            notes: ["The draft was discarded by hand before posting; nothing reached GitHub."],
            diffParts: 2)
        return (row, artifacts)
    }

    /// The onboarding model for one step. `repos` and the tool rows are what the step's checks would have found.
    @MainActor static func onboarding(_ step: OnboardingStep, now: Date, paths: Paths, running: Bool = false) -> OnboardingModel {
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
            if running {
                state.firstSweep = .running
                strips = Store.strips(from: firstSweepRun(now, landed: false))
            } else {
                strips = Store.strips(from: firstSweepRun(now, landed: true))
                let landing = OnboardingSummary.landing(strips, posting: .comment, repo: "lumen/api")
                state.firstSweep = .finished(reviews: landing.reviews, summary: landing.text)
            }
        }
        return OnboardingModel(fixture: state, paths: paths, tools: tools, repos: discovered,
                               repoList: .loaded, liveStrips: strips)
    }
}
