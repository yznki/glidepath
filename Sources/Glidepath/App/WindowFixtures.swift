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
                    kind: String? = nil, target: String? = nil, tendAction: String? = nil, tendCheck: String? = nil) -> RunState {
        RunState(id: id, started: start, finished: minutes.map { start.addingTimeInterval($0 * 60) },
                 repos: repos.map { slug in RepoState(slug: slug, prs: prs.filter { $0.0 == slug }.map(\.1), error: nil) },
                 tokens: tokens, error: nil, kind: kind, target: target, tendAction: tendAction, tendCheck: tendCheck)
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
        // Tending is on for lumen/api only; the Tending block shows the switch, the repo, and the other settings.
        api.tend = true
        config.tend.enabled = true
        config.tend.autopilot = true
        config.tend.roundsPerDay = 5
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
            snap.runs = [sweepMorning(now)]
        }
        if name == "now-dry-run" {
            // The first sweep's dry run holds the lock. It is not the current run, so the run is nil.
            snap.run = nil
            snap.dryRunning = true
            snap.dryRun = firstSweepRun(now, landed: false)
        }
        if name == "approach" || name == "approach-drawer" {
            addTend(&snap, now: now)
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

    // MARK: Tending

    /// Adds tend's state to a fixture snapshot: the approach chart, the tower, today's rounds, the user's call and a
    /// playbook. The planes are one morning in lumen/api: a stack of three landing in order, a fix in flight, a held fix,
    /// a stuck PR, a PR waiting on Gadi, and a draft.
    static func addTend(_ snap: inout Snapshot, now: Date) {
        snap.tendOn = true
        snap.approach = approachSnapshot(now)
        snap.tower = towerLines(now)
        snap.tendRounds = tendRounds(now)
        snap.calls = ["lumen/api#1246/\(gadiCallID)": gadiCall(now)]
        snap.playbooks = ["lumen/api": playbook(now)]
    }

    /// The call id of Gadi's thread on #1246, as tend keeps it in the PR's state.
    static let gadiCallID = "PRRT_kwDO1246gadi"

    /// Gadi's "use a unique index instead" on #1246, with the draft tend wrote for it.
    static func gadiCall(_ now: Date) -> YourCall {
        YourCall(id: gadiCallID, kind: "thread", author: "Gadi", quote: "use a unique index instead",
                 draft: "The index exists (migration 0412). This guard covers the retry window the index cannot.",
                 at: at(14, 21, now))
    }

    static func approachSnapshot(_ now: Date) -> ApproachSnapshot {
        let slug = "lumen/api"
        func plane(_ n: Int, _ title: String, phase: ApproachPhase, marker: Int, lane: Int, stack: Int? = nil,
                   label: String, waitingOn: String? = nil, ci: String, off: Bool = false,
                   gates: [Gate]) -> ApproachPlane {
            ApproachPlane(slug: slug, n: n, title: title, url: "https://github.com/\(slug)/pull/\(n)", phase: phase,
                          marker: marker, label: label, waitingOn: waitingOn, lane: lane, stackIndex: stack, off: off,
                          gates: gates, ci: ci)
        }
        func gate(_ name: String, _ state: GateState, _ detail: String, who: String? = nil) -> Gate {
            Gate(name: name, state: state, detail: detail, who: who)
        }
        let passed = [gate("CI", .ok, "4 of 4 checks green"), gate("Threads", .ok, "All resolved"),
                      gate("Approval", .ok, "Approved"), gate("Ready", .ok, "No conflicts with main")]
        let planes = [
            plane(1301, "Notification schema: migration and backfill", phase: .cleared, marker: 3, lane: 0, stack: 1,
                  label: "Ready to land", ci: "passed", gates: passed),
            plane(1302, "Notification engine on the new schema", phase: .waiting, marker: 2, lane: 0, stack: 2,
                  label: "Waiting on Basem", waitingOn: "Basem", ci: "passed",
                  gates: [gate("CI", .ok, "4 of 4 checks green"), gate("Threads", .ok, "All resolved"),
                          gate("Approval", .wait, "Waiting on Basem", who: "Basem"),
                          gate("Ready", .wait, "Behind notify/schema")]),
            plane(1303, "Notification digest emails", phase: .waiting, marker: 1, lane: 0, stack: 3,
                  label: "Waiting on Gadi", waitingOn: "Gadi", ci: "passed",
                  gates: [gate("CI", .ok, "4 of 4 checks green"), gate("Threads", .ok, "All resolved"),
                          gate("Approval", .wait, "Waiting on Gadi", who: "Gadi"),
                          gate("Ready", .wait, "Behind notify/engine")]),
            plane(1253, "feat(ops): picture card views for pilots, clients and sites", phase: .flying, marker: 0, lane: 2,
                  label: "Glidepath fixing Unit Tests · try 1 of 2", ci: "failed",
                  gates: [gate("CI", .work, "Unit Tests failing", who: "Glidepath"), gate("Threads", .ok, "All resolved"),
                          gate("Approval", .wait, "Waiting on Basem", who: "Basem"),
                          gate("Ready", .wait, "Checks not all green")]),
            plane(1360, "fix(api): retries return the stored response", phase: .holding, marker: 1, lane: 1,
                  label: "Fix held · approved, pushing cancels it", ci: "passed",
                  gates: [gate("CI", .ok, "3 of 3 checks green"), gate("Threads", .ok, "All resolved"),
                          gate("Approval", .ok, "Approved"), gate("Ready", .wait, "Behind main", who: "you")]),
            plane(1246, "fix(api): repeated create and retry requests return the first result", phase: .holding,
                  marker: 2, lane: 3, label: "Stuck · Unit Tests failed twice on this head", ci: "failed",
                  gates: [gate("CI", .wait, "Unit Tests failing", who: "you"),
                          gate("Threads", .wait, "1 open", who: "you"),
                          gate("Approval", .wait, "Changes requested by Gadi", who: "you"),
                          gate("Ready", .wait, "Conflicts with main", who: "you")]),
            plane(1318, "Card views: pilot certifications list", phase: .waiting, marker: 1, lane: 4,
                  label: "Waiting on Gadi · code owner · 26 h", waitingOn: "Gadi", ci: "passed",
                  gates: [gate("CI", .ok, "3 of 3 checks green"), gate("Threads", .ok, "All resolved"),
                          gate("Approval", .wait, "Waiting on Gadi", who: "Gadi"),
                          gate("Ready", .wait, "Blocked by branch rules")]),
            plane(1330, "Certifications: draft for self-review", phase: .taxiing, marker: 0, lane: 0,
                  label: "Draft", ci: "pending",
                  gates: [gate("CI", .wait, "1 running"), gate("Threads", .ok, "All resolved"),
                          gate("Approval", .wait, "No review yet"), gate("Ready", .none, "Draft")]),
        ]
        let needs = [
            NeedsItem(id: "\(slug)#1360/held", slug: slug, n: 1360, title: "fix(api): retries return the stored response",
                      kind: "held", detail: "Fix held · approved, pushing cancels the approval"),
            NeedsItem(id: "\(slug)#1246/stuck", slug: slug, n: 1246,
                      title: "fix(api): repeated create and retry requests return the first result", kind: "stuck",
                      detail: "Stuck · 2 tries on this head used"),
            NeedsItem(id: "\(slug)#1246/\(gadiCallID)", slug: slug, n: 1246,
                      title: "fix(api): repeated create and retry requests return the first result", kind: "call",
                      detail: "Your call · Gadi: \"use a unique index instead\" · draft reply ready"),
        ]
        return ApproachSnapshot(updated: now, planes: planes, needs: needs, queued: 2, status: nil,
                                working: "Fixing Unit Tests on #1253", nextLook: now.addingTimeInterval(180))
    }

    static func towerLines(_ now: Date) -> [TowerLine] {
        [
            TowerLine(at: at(14, 32, now), slug: "lumen/api", n: 1253, text: "#1253 reproducing Unit Tests · npm test -w lumen",
                      detail: nil, amber: false),
            TowerLine(at: at(14, 21, now), slug: "lumen/api", n: 1246, text: "#1246 Council 2–1, chair: act",
                      detail: nil, amber: false),
            TowerLine(at: at(14, 20, now), slug: "lumen/api", n: 1246,
                      text: "#1246 replied to 2 threads, resolved 2 · 1 needs you",
                      detail: "Fixed in a91c03e: return the stored response on retry\n-  return create(req)\n+  return existing ?? create(req)",
                      amber: true),
            TowerLine(at: at(13, 55, now), slug: "lumen/api", n: 1318, text: "#1318 reran Browser E2E · runner lost · green",
                      detail: nil, amber: false),
            TowerLine(at: at(13, 10, now), slug: "lumen/api", n: 1330, text: "#1330 self-review fixed 2 findings before review",
                      detail: nil, amber: false),
            TowerLine(at: at(11, 2, now), slug: "lumen/api", n: 1301, text: "#1301 merged main in · 1 conflict in schema.prisma resolved",
                      detail: nil, amber: false),
            TowerLine(at: at(9, 40, now), slug: "lumen/api", n: 1301, text: "#1301 approved by Basem", detail: nil, amber: false),
        ]
    }

    /// Two rounds today: a CI fix on #1246 and a CI fix on #1253, each titled as the CLI titles it.
    static func tendRounds(_ now: Date) -> [RunState] {
        var threadRound = run("fixture-tend-1246", at(14, 20, now), minutes: 4,
                              prs: [row("lumen/api", 1246, "omar", "fix(api): repeated create and retry requests", verdict: nil,
                                        reason: "Agreed with 2 of 3 comments. Fixed both in one commit, replied, resolved.")],
                              tokens: 38_000, kind: "tend", target: "pr:lumen/api#1246", tendAction: "fixed")
        // Two agreed threads, fixed and posted; Gadi's disagreement waits as a draft, and a council sat on it.
        threadRound.tendThreads = [
            ThreadVerdict(id: "PRRT_kwDO1246basem", author: "Basem", quote: "retry should return the stored body",
                          verdict: "agree", reply: "Fixed in a91c03e: return the stored response on retry.", posted: true),
            ThreadVerdict(id: "PRRT_kwDO1246bot", author: "coderabbit", quote: "missing await on save",
                          verdict: "agree", reply: "Fixed in a91c03e: await the save.", posted: true),
            ThreadVerdict(id: gadiCallID, author: "Gadi", quote: "use a unique index instead",
                          verdict: "disagree", reply: gadiCall(now).draft, posted: false),
        ]
        threadRound.council = [
            CouncilRecord(topic: "Gadi's thread",
                          seats: [Seat(lens: "correctness", vote: "act", reason: "Index exists (migration 0412). The guard covers the retry window the index can't.", confidence: "high", security: false),
                                  Seat(lens: "intent", vote: "act", reason: "Gadi's real worry is duplicates; the reply should cite the index.", confidence: "medium", security: false),
                                  Seat(lens: "risk", vote: "hold", reason: "Two sources of truth for uniqueness; drop the guard.", confidence: "medium", security: false)],
                          chair: "act", outcome: "act"),
        ]
        return [
            threadRound,
            run("fixture-tend-1253", at(11, 40, now), minutes: 3,
                prs: [row("lumen/api", 1253, "ines", "feat(ops): picture card views", verdict: nil,
                          reason: "Unit Tests failed on a stale snapshot. Updated it to the new contract; no assertion removed.")],
                tokens: 22_000, kind: "tend", target: "pr:lumen/api#1253", tendAction: "fixed"),
        ]
    }

    static func playbook(_ now: Date) -> Playbook {
        Playbook(commands: [Playbook.Command(command: "npm test -w lumen -- --run", verified: 9, date: now)],
                 lessons: [Playbook.Lesson(text: "Gadi prefers DB constraints over app guards; cite them in replies",
                                           source: "from your edit", date: now.addingTimeInterval(-3 * 86_400)),
                           Playbook.Lesson(text: "Never touch prisma/migrations/*; add a new migration",
                                           source: "you taught", date: now.addingTimeInterval(-7 * 86_400))])
    }

    /// The popover with tending on: the 1:00 PM sweep's cards and the approach strip.
    static func popoverTend(_ now: Date) -> Snapshot {
        var snap = Fixtures.idleChanges(now)
        addTend(&snap, now: now)
        return snap
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
