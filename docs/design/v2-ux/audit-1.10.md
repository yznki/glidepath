# Glidepath UX audit, v1.10.0 delta (tending, autopilot, Approach)

Follows `audit.md` (v1.5.0). Same scope: structure, flows, density, wording, affordances. Colour, glass and the Gotham look are out of scope.

**Method.** `origin/main` (1eff468, v1.10.0, 114 commits after the 1.5 checkout) in a throwaway worktree. Stock snapshotter (`glidepath --snapshot`, fixtures only, run with an empty `HOME`, so nothing of the live config, state, Keychain or the running autopilot was read). Extra surfaces came from a scratch edit of `Snapshotter` in that worktree (taller frames, tend fixtures in Now and History). The checked-out branch and the repo source were not changed. Every claim comes from a screenshot (`screens/110-*.png`) or from the code at the cited line. Spec intent: `docs/design/sdlc-partner/spec.md`.

Screenshot names: `110-popover-*` = menu bar popover, `110-win-*` = main window. Frames are 1100 × 720 pt (the default window) unless the name ends in `-full`, `-tend` or `-runs` (taller, so everything shows).

**Fixture caveats.** Counts, PR titles and tower text are fixtures. Where a finding depends on live data (for example how many tend rounds reach History) the code path is cited and the screenshot only illustrates it. The Split builder, call Edit sheet and menu bar dot are drawn from fixtures or read from code; hover, hold-fill, drag and the 30 fps chart animation were not captured.

---

## 1. Surfaces added or changed in 1.6–1.10

Version of each: 1.6 watch + CI, 1.7 comments, 1.8 landing, 1.9 extras (self-review, nudges, Linear, briefing, playbook), 1.10 split. Unchanged files in the range (so every 1.5 finding on them stands): `Onboarding*.swift`, `Repos.swift`, `Schedule*.swift`, `Popover/Card.swift`, `RunCard.swift`, `FlightRecorder.swift`.

### 1.1 New surfaces

| Surface | Purpose | Controls (count) | Numbers / marks | How reached | What it duplicates |
|---|---|---|---|---|---|
| **Approach** section (`ApproachSection.swift:9`, `110-win-approach.png`, `110-win-approach-full.png`) | The home of tending: every open PR of yours as a plane on a chart, what needs you, the tower log, the briefing | Autopilot pill (1), chart glyphs (up to N, 22 pt hit radius), briefing Dismiss (1), tower lines (30, tap = expand), plus every Needs row's buttons (see §1.2) | status line, "9 in the air" (sidebar), "NEEDS YOU 7", legend (3 colours), 4 marker labels, "live" | Sidebar item 2 (⌘2); popover "Open Approach" / strip buttons | Needs you (Now has the same items + 2 more kinds); next look (popover); history (Tower vs History cards); Settings > Autopilot (same switch) |
| **Approach chart** (`ApproachChart.swift`) | Place each PR on a glide slope: lane = stack, x = furthest marker passed, colour = who owns the move | Tap a glyph = open drawer. No other control | up to 5 lanes, 4 markers (Outer · CI, Middle · Review, Inner · Ready, Runway · Landed), per-plane `#n` + one-line label | Approach, and a 360 × 84 pt non-interactive copy in the popover | The drawer's 4 "markers" and 4 "gates" (two checklists with different names, §1.2); the Needs rows (same PR, second encoding) |
| **PR drawer** (`ApproachDrawer`, `110-win-approach-drawer.png`) | One PR's gates, changes since review, split state, today's rounds, council cards, teach field, lessons, tend switch | Close, Split… / Review split, teach field + Teach, tend switch, 3 to 6 lesson rows, thread/council cards = about 10 | 4 markers, 4 gates (state + who), "N of 5" rounds, "N lessons", "verified N×" | Click a glyph on the chart. **Not** reachable from a Needs row, the tower or the popover | Settings > Playbook (lessons, teach); History cards (rounds); Needs rows (the held/stuck state) |
| **Needs you** list in Approach (`TendNeedRow`, `ApproachSection.swift:407`) | Everything tend wants a human for: 7 kinds (held fix, stuck, your call, ready to land, main broke, split proposed, waiting on reviewer) | 12 distinct verbs across the 7 kinds: Discard, Hold to push, Open PR, Try again, Edit, Post reply, Hold to land, Open revert PR, Keep as one, Review, Ping *login*, Pinged today | count in header, per row: mark glyph (`? ↓ ÷ !`), state word in amber, slug #n | Approach (left column) | The same rows appear in Now (§1.3); 3 strips in the popover |
| **Tower** (`ApproachSection.swift:212`) | Live log of what tend did: newest 30 lines | tap a line to expand its detail (commit, patch) | clock time, text, amber = needs you | Approach (right column, fixed 340 pt) | History cards (a second record of the same rounds), drawer "Rounds today" |
| **Morning briefing** (`BriefingCard.swift`) | Once a day at `briefing_time`: landed, blocked, "Glidepath did" | Dismiss (1) | headline "2 landed, 1 blocked.", sentence with rounds/threads/tokens, 3 columns | Top of Approach until dismissed; one notification | Tower, History (the same events, summarised); no other entry point |
| **Call Edit sheet** (`CallEditCard`, `110-win-approach-call-edit.png`) | Edit and post a draft reply to a reviewer | Cancel, Post reply, text editor, scrim tap = close | reviewer quote, reply | Needs row "Edit" (in Approach or Now) | Needs row "Post reply" posts the same draft unread |
| **Split builder** (`SplitBuilder.swift`, `110-win-approach-split.png`) | Review and edit a proposed split of a big PR into 2 to 6 stacked PRs | N part columns (title field, file chips draggable or via context menu), Keep as one, Cancel, Hold to build stack | file count, part count, validation line | Needs row "Review" (split), drawer "Review split" | Drawer "Split…" plans; the Needs row proposes; builder is the third place for the same PR's split |
| **Popover tend block** (`ApproachPopoverBlock`, `110-popover-tend.png`) | Mini chart, up to 3 needs, next look | up to 3 strips: Hold to land / Open revert PR (holds) or "Open" / "Review" (just open Approach), "Open Approach" | "Next look in 2 min" | Popover, only while tending is on | Approach (whole); Needs rows; the popover's own "2 waiting for you" (a different list) |
| **Settings > Tending** (`Settings.swift:418`, `110-win-settings-tending.png`) | Switches and limits for tend | 12 rows + one switch per repo: Tend my PRs, repo switches, Approved fixes (2-way), Rounds per PR a day (slider), Landing (3-way), Autopilot, Self-review, When Glidepath disagrees (2-way), Claude account (2-way + Sign in…), Usage reserve (slider), Quiet hours (text), Linear (secure field + Save/Remove) | "5", "40%" | Settings > chip "Tending" | Approach pill (Autopilot); Repos page (second repo list); Reviewing > "When a review is ready" (posting mode, different words) |
| **Settings > Playbook** (`SettingsPlaybook.swift`, `110-win-settings-playbook.png`) | See verified commands, edit or delete lessons, teach a rule | repo picker (segmented, one segment per tended repo), Edit, Delete per lesson (about 2 × N), teach field + Add | "verified 9×", source + date per lesson | Settings > chip "Playbook" | Drawer "Learned in repo" + Teach; CLI `glidepath teach` |
| **Menu bar dot** (`MenuBarLabel.swift:211-219`) | 4 pt amber dot while a tended PR "holds" | none | a dot | glyph | Badge from review drafts (existing `glyphBadge`): two signals on one glyph, counting different things |
| **Notifications** (`Store.swift:424-470`) | One per new need, per landed PR, per briefing | none | titles "#n needs you", "#n is ready to land", "Main broke after #n", "#n landed", "Glidepath briefing" | system | the popover and Needs rows |
| **Tending off** (`110-win-approach-off.png`) | Empty state | 1 button "Turn on in Settings" | none | Approach with tend off | n/a |

### 1.2 Changed surfaces

| Surface | What changed | Evidence |
|---|---|---|
| Sidebar (`Sidebar.swift`) | 5 → **6** items (Approach inserted second, shortcuts ⌘1–⌘6). Approach shows "N in the air" (planes not landed) in 10 pt faint text. The Now badge still counts only review drafts and too-large PRs (`waitingCount`, `Store.swift:268`) | `110-win-now-tend.png`: badge 2, header 9 |
| Now (`Now.swift:30-32, 180-188`) | "Needs you" count = held + too large + **all tend needs**; tend rows are mixed into the same list after the review rows. Call Edit and Split builder overlays are also hosted here | `110-win-now-tend.png` |
| Now / History run cards (`RunDigest.swift:62-68, 90-118`) | A tend round is a run card titled "Fixed CI on #1246", "Reran …", "Answered threads on …", "Merged the base into …", "Lessons tidied for repo", "Self-review of #n" (a dry run). One row, no verdict, no repo name | `110-win-now-tend-runs.png`, `110-win-history-tend.png` |
| Popover (`Popover.swift:219`) | One block inserted between digest/update and footer: +279 pt height (341 → 620 pt in `tend` vs `drafts` state) | `110-popover-tend.png` |
| Settings | 6 → **8** chips; 30 → **46** rows (+12 Tending, +4 Playbook) plus per-repo switches and per-lesson rows; default view still shows only the first 9 rows (Reviewing), so Tending sits below the fold | `110-win-settings-full.png` (11 360 px tall at 2×) |
| HoldButton (`HoldButton.swift`) | A 28 pt `compact` variant for rows, so holds now sit inline on Needs rows | `110-win-approach.png` |
| Shortcuts | 54 → **55** entries (`showApproach`); every section shortcut renumbered | `Shortcuts.swift:182-188` |
| Onboarding | **Unchanged.** No tending step, no mention. The only invitation is the Approach empty state | `110-win-approach-off.png` |

### 1.3 Counts

| Measure | 1.5 | 1.10 |
|---|---|---|
| Sidebar items | 5 | 6 |
| Settings rows (static `Row`s) | 30 | 46 (+ N repo switches + lessons + commands) |
| Settings chips | 6 | 8 |
| Distinct point sizes app-wide | 18 | 20 (12 pt used 119×, was 92; 13 pt 75×, was 52) |
| Hold-to-act buttons | 3 (post, stop, reset) | 7 (+ push, land, revert PR, build stack) |
| Confirm models for Discard | click + alert | click + alert (reviews), **click, no confirm** (fix, reply, 3 tend Discards: `ApproachSection.swift:504,552`) |
| Needs-you row kinds | 2 (held review, too large) | 9 |
| Shortcuts | 54 | 55 |

---

## 2. Navigation map, v1.10

```
Menu bar glyph  (6 states from 1.5) + amber dot while a tended PR "holds"      (MenuBarLabel.swift:211)
  click or ⌥⌘G ........ Popover (110-popover-tend.png), 341 pt idle-changes, 620 pt with tending on
      stats row · run/stop · window · "N waiting for you" + review cards
      digest line · update line
      TEND BLOCK: mini chart · up to 3 strips · "Next look in N min" · "Open Approach"
         strip "#n ready to land"  -> Hold to land   (acts in place)
         strip "Main broke after #n" -> Open revert PR (hold, acts in place; label does not say hold)
         every other strip (held fix, stuck, call "Review", blocked, split) -> "Open" / "Review" = open Approach, nothing else
      ellipsis menu (unchanged: Open Glidepath, Pause, Open log, History, updates, login, Quit)

Main window
  Onboarding (unchanged; no tending step)
  Sidebar: Now · Approach · History · Repos · Schedule · Settings      (⌘1..⌘6)
    Now ......... Review… menu · NEEDS YOU (review rows + tend rows, 9 kinds, one list) · RECENT (3 newest runs of ANY kind)
    Approach .... header: working/next-look line · Autopilot pill
                  [Briefing card] · Chart · NEEDS YOU (7 kinds) | TOWER (30 lines)
                  chart glyph -> Drawer (9 sections): markers · changes since review · gates · split · rounds today
                                 (+ thread verdicts, council cards) · teach · learned (6 lessons, 3 commands) · tend switch
                  Needs row -> Edit (call sheet) · Review (Split builder)
                  Tending off -> empty state, button to Settings
    History ..... every run card by day, now including tend rounds, self-reviews, lesson tidies
    Repos ....... unchanged (no tending control; Settings has a second repo list)
    Schedule .... unchanged; tend's 5-minute cadence, quiet hours and briefing time are not here
    Settings .... search · 8 chips (Reviewing, Tending, Playbook, Notifications, Menu bar, Look, Budget, Advanced) · 46 rows
                  Tending: 12 rows + one switch per repo   Playbook: repo picker + commands + lessons + teach
```

| Count | 1.5 | 1.10 |
|---|---|---|
| Sidebar items | 5 | 6 |
| Sections that can hold a "needs you" item | 2 (popover, Now) | 4 (popover, Now, Approach, + menu bar dot) |
| Places that show Autopilot state | 0 | 2 (Approach pill, Settings row). Not in the popover, Now, sidebar or glyph |
| Places to switch tending off | 0 | 4 (Settings switch, per-repo switch, per-PR drawer switch, GitHub label) + global Pause |
| Places a PR's playbook is edited | 0 | 3 (drawer teach, Settings > Playbook, CLI) |
| Depth: popover → a held tend fix pushed | n/a | 3+ (glyph, Open, find the row on Approach, hold 0.9 s). The popover strip cannot push it |
| Depth: popover → stop tending | n/a | no way; Pause (2) pauses reviews too, Settings switch (3) uninstalls the job |

---

## 3. The four questions

### 3.1 "What is autopilot doing to my PRs right now?"

| Step | Where | Cost | Verdict |
|---|---|---|---|
| Is anything running? | Menu bar glyph does **not** animate for a tend round (a tend run is never `current`: `Store.swift:310`, `TendCommand.swift:567`). Popover shows "Next look in N min" and the mini chart, never the working line | glance: no; popover: no | **Not answered** where the user looks first |
| What is it working on? | Approach header, top right: "Fixing Unit Tests on #1253" (12 pt, muted, `ApproachSection.swift:100-113`) | popover > Open Approach (3 interactions) | Answered, small, one line |
| Is autopilot even on? | Approach header pill (28 pt, `help` tooltip only) or Settings > Autopilot | 3 | Not shown in the popover, Now, sidebar or glyph |
| What will autopilot do on its own? | Settings rows "Approved fixes", "Landing", "When Glidepath disagrees" still show their own values (e.g. "Hold the fix", "Ask me", "Draft for me") although autopilot overrides all three (`Autopilot.swift:39-53`) | n/a | **Contradicts** itself (`110-win-settings-tending.png` shows Autopilot on beside "Hold the fix", "Draft for me") |
| Why is nothing happening? | Header prefers `nextLook`, which the CLI always sets to now + 5 min (`TendCommand.swift:2335`), so the queue reason ("Paused for usage · resets …", quiet hours wait) in `status` is never drawn (`ApproachSection.swift:103-105`). `queued` is never drawn. Usage percent is shown nowhere. Global Pause: tend skips (`TendCommand.swift:301`), Approach still says "Next look in 0 min" (`HeaderCopy.untilText` clamps at 0, `Popover.swift:185`) | n/a | **Not answered** |

### 3.2 "What did it do?"

| Source | Content | Gaps |
|---|---|---|
| Tower (Approach, right column) | 30 newest lines, clock time + text, amber when it needs you | No date (yesterday and today look alike), text-only `#n` (the slug is stored but not drawn, `Tend.swift:194`), no PR title, no link to the PR or the drawer, no marker for "autopilot did this vs you did". Fixed 340 pt column |
| Drawer > Rounds today | Per PR: round cards, thread verdicts (✓ ✗ ?), council seats | Only today; reached by clicking a 22 pt glyph on the chart |
| History / Now > Recent | One card per round: "Fixed CI on #1246 · Fixed CI on #1246 Agreed with 2 of 3…" (title repeated as the bold lead, `RunDigest.swift:62-68`), no repo, tokens + duration | Interleaved with reviews, not filterable; Now's Recent shows only the newest 3 runs of any kind (`Now.swift:49`, `Reviews.swift:258`) |
| Morning briefing | counts + landed / blocked | Once a day, dismiss deletes it from view (`BriefingFile`), top of Approach only |
| Notifications | only needs, landings, briefing | Routine rounds are silent by design |
| GitHub | commits, replies | outside the app |

There is no "since I last looked" view.

### 3.3 "What needs me?"

| Surface | What it shows | Count shown |
|---|---|---|
| Sidebar Now badge | review drafts + too-large only | **2** (`Sidebar.swift:88`, `Store.swift:268`) |
| Now header | review rows + tend rows | **9** (`Now.swift:32`) |
| Approach header | tend rows only | **7** |
| Sidebar Approach | planes not landed, "in the air" | **9** (not a needs count, same weight of text) |
| Popover | "2 waiting for you" (review) + at most 3 tend strips, no "+4 more" | 2 + 3 of 7 (`ApproachSection.swift:306`) |
| Menu bar | badge: review drafts; amber dot: planes in `.holding` only. Ready to land (phase `cleared`), revert, split proposed and blocked/ping do **not** light it | dot, not a count |
| Notifications | every new need, including "waiting on reviewer" and "split proposed" | one each |

Resolving a need: Approach/Now rows act in place. The popover acts in place only for land and revert; held fix, stuck, call, split, blocked just open Approach.

### 3.4 "Stop it."

| Goal | Route | Cost |
|---|---|---|
| Stop the round that is running now | **None.** Stop (hold) and ⌘. kill `run.pid`, which only the sweep writes (`Store.swift:600-606`; `Run.swift:170,388`; no write in `TendCommand`). A running tend round has no stop in the app | n/a |
| Stop autopilot acting on its own | Approach pill (1 click, no confirm), or Settings. This changes policy only; rounds, fixes and pushes continue | 1 |
| Stop everything for a while | Global Pause (popover menu, Schedule, ⇧⌘P). Labelled "scheduled sweeps"; Approach shows nothing; stale "Next look" | 2 |
| Stop tending for good | Settings > Tending > "Tend my PRs" off. Uninstalls the launchd job (`Settings.swift:411`), no message about the job beyond errors | 3 |
| Stop one PR | Approach > click its glyph > scroll the drawer to the bottom > switch; or the `glidepath:hands-off` label on GitHub | 3 + scroll |
| Undo a lesson | Settings > Playbook > Delete (lessons apply at once, no preview) | 3 |

---

## 4. New problems, ranked

Same format as `audit.md` §4. Severity: **S1** blocks or misleads a main job or can hurt, **S2** costs steps or trust every day, **S3** clutter or polish. IDs are `N1…` so they do not clash with the 1.5 list.

| # | Sev | Problem | Where (file:line, screenshot) | Heuristic |
|---|---|---|---|---|
| N1 | S1 | **Autopilot is a one-click pill, and what it does is not visible where you set it.** It flips merging, replying and resolving without asking with no confirm, in a 28 pt capsule whose only explanation is a tooltip, while landing one PR by hand takes a 0.9 s hold. Turning it on does not change the three rows that it overrides (Approved fixes, Landing, When Glidepath disagrees), so Settings shows "Hold the fix / Ask me / Draft for me" while autopilot is on. | `ApproachSection.swift:116-136`; `Settings.swift:439-475`; `Core/Autopilot.swift:39-53`; `ConfigEdit.swift:266`; `110-win-approach.png`, `110-win-settings-tending.png` | Error prevention (N5), visibility (N1), consistency (N4) |
| N2 | S1 | **Tending cannot be stopped from the app, and no stop is where you'd look.** Stop and ⌘. act on the sweep only; a tend round writes no `run.pid`. Autopilot off stops decisions, not work. Pause is worded for sweeps and Approach does not reflect it. The real off switches are 3 deep (Settings), at the bottom of a drawer opened by a 22 pt glyph (per PR), or a GitHub label. | `Store.swift:600-606`; `Run.swift:170,388`; `TendCommand.swift:301, 567`; `ApproachSection.swift:951-967`; `110-win-approach-drawer.png` | User control and freedom (N3), N1 |
| N3 | S1 | **"Why is it idle?" has no answer.** The header shows `nextLook`, which the writer always sets, so the usage-pause and quiet-hours reason is unreachable code; `queued` is never drawn; usage percent is shown nowhere. Paused or stale state reads "Next look in 0 min". A tend round does not animate the glyph or the popover, so the first surfaces say "idle" while Claude works. | `ApproachSection.swift:100-113`; `TendCommand.swift:2333-2335`; `Popover.swift:185`; `Store.swift:310`; `110-popover-tend.png` | Visibility of system status (N1) |
| N4 | S1 | **Six surfaces, six different "needs you" counts.** Sidebar badge 2, Now header 9, Approach 7, sidebar "9 in the air", popover 2 + 3 strips with no overflow, menu bar dot only for held/stuck planes. The Now badge disagrees with the Now header on the same screen. | `Sidebar.swift:88-89`; `Store.swift:268`; `Now.swift:32`; `ApproachSection.swift:306`; `MenuBarLabel.swift:211-219`; `110-win-now-tend.png` | Consistency (N4), N1, trust |
| N5 | S1 | **The popover shows tend needs it cannot resolve.** Only land and revert act in place; held fix ("Fix held"), stuck, call, split and blocked show "Open"/"Review", which only opens Approach (not the PR, not the call). A held fix needs: glyph → Open → find the row → hold. "Open revert PR" is a 0.9 s hold with no sign of it. Strips name no repo; titles truncate ("Unit tests failed on the merge…"). The popover grows from 341 to 620 pt. | `ApproachSection.swift:336-384, 366-378`; `110-popover-tend.png` | Affordance, N4, density, N8 |
| N6 | S2 | **Tend rounds flood Now > Recent and History.** There is no filter on run kind. Now's Recent is "the 3 newest runs", so a day of rounds (5 per PR per day cap) pushes sweeps out of it. Cards have no repo, repeat their title (`Fixed CI on #1246` as title and as bold lead), and sit beside reviews. Self-review dry runs and lesson tidies get cards too. | `Now.swift:44-50`; `Reviews.swift:151, 258`; `RunDigest.swift:62-68, 105-118`; `110-win-now-tend-runs.png`, `110-win-history-tend.png` | N8 minimalism, N4, signal vs noise |
| N7 | S2 | **The Needs list is 9 kinds and 12 verbs in one column, in three copies.** The same rows live in Now, Approach and (3 of them) the popover, and Now's count mixes them with review rows. Holds: Hold to post, push, land, build stack; but "Open revert PR" is also a hold. Discard means three things (a held review, a held fix, a draft reply) and none of the tend ones confirm. Two "Review" buttons mean different things (open the split builder; open Approach). | `ApproachSection.swift:485-566`; `Now.swift:180-188`; `110-win-now-tend.png` | N4, N5, N2 |
| N8 | S2 | **The Approach chart cannot show a real stack.** 5 lanes (`laneCount`), followers trail by 90 and clamp at x = 60, so a 21-PR stack (the Notification center) piles planes 9 to 21 on one point; a 6th lane shares lane 5. The chart is a Canvas with no accessibility labels and no list alternative. A plane opens only by hitting a 22 pt radius; Needs rows and tower lines do not open the drawer. | `ApproachChart.swift:19, 56-75, 160-170`; `110-win-approach.png` (labels overlap lane lines and the legend) | Accessibility, affordance, N7 |
| N9 | S2 | **Approach's first screen hides what needs you.** With the briefing (22 pt headline + 3 columns) and the 330-unit chart, "Needs you" starts at the fold in the 1100 × 720 window. Tower is a fixed 340 pt column with no dates; needs titles truncate at 1 line ("fix(api): repeated create and retr…"); the same PR appears twice (stuck + call). | `ApproachSection.swift:40-57, 178-185, 456-474`; `110-win-approach.png` | Hierarchy, density, N6 |
| N10 | S2 | **The drawer is nine stacked sections with two checklists.** Markers (Outer · CI, Middle · Review, Inner · Ready, Runway · Landed) and gates (CI, Threads, Approval, Ready) are both "where is this PR", with different names and a different grain. Below them: split, rounds, thread verdicts, council cards, teach, 9 lesson/command rows, switch. | `ApproachSection.swift:583-594, 632-721`; `110-win-approach-drawer.png` | Progressive disclosure, N8 |
| N11 | S2 | **Settings grew 30 → 46 rows, and the new ones act on each other.** Turning on "Tend my PRs" also sets advisor to Opus, self-review on and Landing to Ask me, while its caption says "fixes failing CI". The Tending block has a second repo list (Repos has none). 10 knobs are config-only (`tries_per_head`, `max_fix_lines`, `advisor`, `max_usd_per_session`, `council_per_day`, `registries`, `nudge_hours`, `briefing_time`, `split_over_lines`, `merge_method`). Quiet hours is a free-text DSL ("22:00-07:00,sat,sun") committed on Enter, a third way to enter times beside the dial and the 24 h text. | `Settings.swift:62-92, 418-513`; `ConfigEdit.swift:222-231`; `QuietHoursField.swift`; `Core/Config.swift:138-168`; `110-win-settings-full.png` | Hick's law, N2, N4, recognition vs recall |
| N12 | S2 | **Three places for one playbook.** Drawer (read 6 lessons + 3 commands, Teach), Settings > Playbook (edit, delete, teach; repo picker is a segmented control with one segment per repo), CLI `teach`. Lessons apply immediately with no preview or per-lesson on/off; provenance text ("pushback", "consolidated", "from your edit") is jargon. | `ApproachSection.swift:879-929`; `SettingsPlaybook.swift:15-45`; `110-win-settings-playbook.png` | N4, N6, scalability |
| N13 | S2 | **Council and autopilot decisions show as raw votes, and not as "who decided".** Council appears as three seat cards in the drawer and one tower line ("Council 2–1, chair: act"); the plane, the row and the History card do not say that the action was autonomous. The briefing says "1 council". | `ApproachSection.swift:807-870`; `Tend.swift:194-201`; `110-win-approach-drawer.png` | Visibility (N1), N2 |
| N14 | S2 | **The briefing has one entry point and one exit.** It appears only above the Approach chart (and as one notification), pushes the chart down, and Dismiss removes it for good. It is not in Now or the popover. | `ApproachSection.swift:44-48`; `BriefingCard.swift`; `110-win-approach.png` | Recognition, N3 |
| N15 | S2 | **Approach is a top-level item for everyone, and onboarding never mentions it.** New users see "Approach" second in the sidebar; with tending off it is a dead page ("Turn on in Settings"), then Settings > Tending > switch > per-repo switch: 4 steps. The spec's "stays quiet unless it needs you" is met by the data, not by the navigation. | `ApproachSection.swift:273-288`; `Onboarding.swift` (unchanged); `110-win-approach-off.png` | N8, progressive disclosure |
| N16 | S3 | **Split builder is a 820 pt modal that builds for hours with no progress.** 3 columns of mostly empty space; chips show the basename only, so two `index.ts` files are indistinguishable (path is a tooltip); Escape closes but the scrim does not (inverse of the call sheet); the running build is a one-line caption in the drawer. | `SplitBuilder.swift:102, 225-247`; `ApproachSection.swift:751-762`; `110-win-approach-split.png` | N3, N1 |
| N17 | S3 | **Type scale keeps growing.** 20 sizes (11.5, 12.5, 10.5 added), monospaced 11.5 tower and 10.5 chips, 10 pt faint "N in the air". The sidebar item for the most important new page has the smallest, faintest annotation in the sidebar. | `Sidebar.swift:104-111`; sizes grep; `110-win-approach.png` | Hierarchy, legibility |
| N18 | S3 | **A tend failure shows as one 11.5 pt line on its row.** `tendErrors` is clamped to one line; no log link, no "why" panel (the review sheet's "Why it stopped" is not reused). | `ApproachSection.swift:469-474`; `Store.swift:804-820` | N9 |
| N19 | S3 | **Hold labels do not match their gesture.** "Hold to land" and "Hold to push" say it; "Open revert PR", "Keep as one", "Review", "Post reply" (posts to GitHub unread) do not and are click. | `ApproachSection.swift:491-566` | N4, affordance |

### 4.1 Old problems (`audit.md` §4): better, same, worse

| Old | Verdict | Why |
|---|---|---|
| 1 Hidden holds | **Worse** | 3 → 7 holds; compact rows put them inline; one label ("Open revert PR") hides its gesture; popover strips mix holds and clicks |
| 2 Popover cannot answer status | **Mixed** | Gains "Next look in N min" and strips while tending is on; still no next-sweep time, no working line, failed/paused captions unchanged |
| 3 Too many numbers | **Worse** | Four more counts (§3.3), plus "9 in the air", "7", "N of 5", "N lessons" |
| 4 Setup ends in a dry run | **Same** | Onboarding unchanged; tending has no setup |
| 5 Posting/authors/flags vocabularies | **Same, plus** | Approved fixes / Landing / disagree add a fourth set of policy words |
| 6 Draft / Review / Run / Sweep | **Worse** | "Draft" now has a third meaning (draft reply); "Approved" has three; see §5 |
| 7 Repos page mislabels dots | **Same** | `Repos.swift` unchanged; tending adds no control there |
| 8 Remove repo 5 steps deep | **Same** | |
| 9 Settings 30-row scroll | **Worse** | 46 rows, 8 chips, tending below the fold |
| 10 Three post flows, two safety models | **Worse** | Push, land, build, reply add a third and fourth model (hold; click; click-no-confirm Discard) |
| 11 Popover is four things | **Worse** | +279 pt, a chart, 3 strips |
| 12 Needs rows repeated in Recent | **Same, moved** | Needs rows are now repeated across Now + Approach + popover |
| 13 Run/review vocabulary hides primary action | **Same** | Now header unchanged: "Review…" menu |
| 14 Schedule: two time formats | **Worse** | Quiet hours text DSL, briefing time config-only, tend cadence invisible |
| 15 Failure hard to trace | **Same** | |
| 16 "not posted" unexplained | **Same** | |
| 17 Popover cards overlap | **Same** | visible in `110-popover-tend.png` |
| 18 Micro-caps carry meaning | **Worse** | New caps labels: MORNING BRIEFING, LANDED, BLOCKED, GLIDEPATH DID, NEEDS YOU, TOWER, LIVE, OUTER · CI … |
| 19 Onboarding layout | **Same** | |
| 20 Shortcut surface | **Slightly worse** | +1, renumbering ⌘2–⌘6 |
| 21 Alerts print config syntax | **Same** | |
| 22 System blue/green leaks | **Same** | |
| Better | | The Approach drawer's gates answer "why is this PR not merged?", which 1.5 could not. Needs rows lead with a state word (Ready to land, Stuck, Your call) and name the repo. Settings search "tend" shows the whole block. "Tending is off" is an honest empty state |

---

## 5. Vocabulary: every user-facing concept and noun

61 concepts. 20 existed in 1.5; **41 are new in 1.6–1.10**. "Where" lists the surfaces that print the word.

### 5.1 Reviewing (1.5, still present)

| # | Concept | Meaning | Where |
|---|---|---|---|
| 1 | Sweep | A scheduled pass over all repos | Now cards, popover, menus |
| 2 | Run | Same as sweep, and also any by-hand or tend run | a11y, alerts, History |
| 3 | Review (verb/noun) | Reviewing a PR; Review…, Review now, Review again, Review anyway | Now menu, repo sheet, run rows, popover |
| 4 | Dry run | Review everything, post nothing | Settings, onboarding |
| 5 | Draft (GitHub) | A draft PR | Repos, Settings |
| 6 | Held review / draft | A review kept for you to post | popover, Now, "Hold for me" |
| 7 | Needs you | What waits for you | popover, Now, Approach (now 3 different sets) |
| 8 | Posting mode | Comment / Full review / Draft first (also Post review / Comment only / Hold for me) | onboarding, repo sheet, Settings |
| 9 | Verdict | Approved / Changes / Skipped / No result | rows, popover |
| 10 | Strictness | Review bar | Settings |
| 11 | Authors | Whose PRs get reviewed | onboarding, repo sheet, Settings |
| 12 | Flagged paths | Paths that get a closer look | repo sheet, Settings ("Look closer at") |
| 13 | Rules | Per-repo rubric, Extend / Replace | repo sheet |
| 14 | Code graph | GitNexus blast radius | repo sheet, Settings |
| 15 | Budget | Monthly tokens, pause at budget | Settings |
| 16 | History | Past run cards | sidebar, popover menu |
| 17 | Schedule | Dial, presets, days | sidebar |
| 18 | Pause | Skip scheduled runs (and tend) | popover, Schedule |
| 19 | Run card and folds | A run and its already-reviewed / skipped groups | Now, History |
| 20 | Flight recorder | The PR detail sheet | PR sheet |

### 5.2 Tending and autopilot (new)

| # | Concept | Meaning | Where |
|---|---|---|---|
| 21 | Tending / Tend | Glidepath looking after your own PRs; "Tend my PRs", "Glidepath tends this PR", "Tended repos" | Settings, drawer, Approach empty state, captions |
| 22 | Approach | The section and the metaphor: PRs approaching main | sidebar, popover "Open Approach", chart |
| 23 | Plane | One of your PRs on the chart | chart, drawer |
| 24 | Marker | Outer · CI, Middle · Review, Inner · Ready, Runway · Landed | chart labels, drawer |
| 25 | Gate | CI, Threads, Approval, Ready, each with a state and a "who" | drawer |
| 26 | Runway / Main / Landed | The target and a merged PR | chart, briefing, drawer |
| 27 | In the air | Planes not yet landed | sidebar |
| 28 | Lane / Stack | A chain of PRs on one base, bottom-up | chart, "then #1302, #1303" |
| 29 | Tower | The live log of what tend did | Approach |
| 30 | Drawer | The per-PR panel | Approach |
| 31 | Round | One tend pass on a PR; "Rounds today", "Rounds per PR a day" | drawer, History, Settings |
| 32 | Try | A fix attempt on one head ("try 1 of 2", "tries per head") | chart label, Stuck rows, config |
| 33 | Fix | CI repaired by Glidepath; "Fixed CI on #n" | History, tower |
| 34 | Held fix / push mode | A fix kept for you: "Fix held", "Hold to push", "Approved fixes: Push anyway / Hold the fix" | Needs, Settings |
| 35 | Stuck | Limit reached, needs you: Open PR, Try again | Needs, chart |
| 36 | Your call | A question Glidepath will not decide: Edit, Post reply, Discard | Needs, popover "needs your call" |
| 37 | Disagree policy | "When Glidepath disagrees": Draft for me / Reply and resolve | Settings |
| 38 | Thread verdict | ✓ agree, ✗ disagree, ? unclear on a review comment | drawer |
| 39 | Council | Three judges (correctness, intent, risk) and a chair on a split vote | drawer, tower, briefing ("1 council") |
| 40 | Autopilot | Act without asking | Approach pill, Settings |
| 41 | Hard stop | What still reaches you on autopilot | Autopilot caption, tooltip |
| 42 | Landing | Merge: Ready to land, Hold to land, Off / Ask me / Automatically | Needs, Settings, popover |
| 43 | Revert / Main broke | A merge broke main: Open revert PR; main is watched for an hour | Needs, popover |
| 44 | Merge main in | Conflict handling by merging, not rebasing | tower |
| 45 | Self-review | Glidepath's private review of your PR; "Changes since review" block | Settings, History, drawer, PR body |
| 46 | Nudge / Ping | "Waiting 26 h on gadi", Ping gadi, Pinged today; also "Blocked" in the briefing | Needs, briefing |
| 47 | Hands-off | Label and switch that stop tending a PR | drawer |
| 48 | Briefing | Morning summary: Landed / Blocked / Glidepath did | Approach, notification |
| 49 | Playbook | A repo's verified commands and lessons | Settings, drawer |
| 50 | Verified command | A command seen to pass ("verified 9×") | drawer, Settings |
| 51 | Lesson | A rule learned, with a source (you taught, from your edit, pushback, consolidated) | drawer, Settings, History ("Lessons tidied") |
| 52 | Teach | Add a lesson | drawer, Settings, CLI |
| 53 | Split | Break a big PR into a stack: Split…, Split proposed, Split plan, parts, Keep as one, Hold to build stack | Needs, drawer, builder |
| 54 | Linear | Comment on the issue of a blocked PR; key in Keychain | Settings |
| 55 | Claude account | Same as my claude / Separate account, Sign in… | Settings |
| 56 | Usage reserve | Share of the 5-hour and weekly windows never spent | Settings only; the current usage is shown nowhere |
| 57 | Quiet hours | When heavy work waits; free-text `22:00-07:00,sat,sun` | Settings |
| 58 | Next look / working line | When tend next checks; what it does now | Approach header, popover |
| 59 | Tend round (card) | Fixed CI / Reran / Answered threads / Merged the base / Lessons tidied | History, Now > Recent |
| 60 | Tend job | The second launchd job that runs the 5-minute check | Settings error text |
| 61 | Config-only knobs | advisor, max_usd_per_session, council_per_day, registries, tries_per_head, max_fix_lines, nudge_hours, briefing_time, split_over_lines, merge_method | config.toml only |

### 5.3 Words that mean more than one thing

| Word | Meanings now |
|---|---|
| **Approved** | verdict of Glidepath's review; a PR that people approved ("approved, pushing cancels the approval"); "Approved fixes" (setting) |
| **Draft** | GitHub draft PR; a held review; a draft reply ("Draft for me", "draft reply ready"); "Draft first" (posting mode) |
| **Review** | a verb; a by-hand run; a button that opens the Split builder; a call's button in the popover that opens Approach; "Review split"; "Review anyway"; "Review again"; the self-review; the Review menu |
| **Hold / Held / Holding** | the 0.9 s gesture; a held review; "Hold for me"; "Hold the fix"; "Fix held"; the plane phase `holding` (a stuck PR) |
| **Waiting** | waiting for you (popover, Now); "Waiting on Gadi" (a reviewer owes a move); "waiting" in review row meta; `Waiting on someone` legend |
| **Blocked / Stuck / Held** | three words for "needs a person", used for different states in the briefing, the chart and the rows |
| **Landed** | a merged PR (runway); a review that was posted (`landed` verdict in code) ; "Landing" the action; "Ready to land" |
| **Run / Sweep / Round / Try / Session** | a scheduled pass; a by-hand pass; a tend pass on one PR; an attempt; an agent session |
| **Open** | Open PR (GitHub); Open Approach; Open (popover strip, goes to Approach); Open log; Open revert PR; Open at login |
| **Needs you** | popover (reviews only), Now (reviews + tend, 9), Approach (tend only, 7), sidebar badge (reviews, 2) |

### 5.4 Metaphor layer

Aviation words (approach, plane, runway, tower, gate, marker, lane, "in the air", "flying", "taxiing", "glide", "cleared") sit on top of ops words (round, fix, land, revert, merge, stack). A reader must learn both vocabularies and the map between them (a plane at the "Inner · Ready" marker is a PR that "needs one more gate"). The legend names three states; the code has six phases (`taxiing, flying, waiting, holding, cleared, landed`, `Approach.swift:108`).

---

## 6. What was not captured

- **The live app was not launched** (the user's autopilot is running). All data is fixtures; real tend state, queue reasons, usage windows and a real History were not seen.
- **Animated states**: the 30 fps chart, landing glide, gate spinner, hold-fill, drag in the Split builder; Reduce Motion behaviour.
- **AppKit-backed controls**: text fields (stand-ins offscreen), the Linear secure field, NSAlert confirms (tend actions have none), notification banners.
- **Menu bar amber dot** was read from code (`MenuBarLabel.swift:211`); the stock `menubar.png` strip has no tend state.
- **History with tend rounds** and **Now with tend rows** are from the scratch snapshotter (fixtures merged), not the stock one.
- **A stack of 21** (the real one) was not rendered; the pile-up is derived from `ApproachGeometry.positions` (`ApproachChart.swift:62-78`).
- **Small and large windows**: only the 1100 × 720 default and taller frames. Behaviour when the window is smaller than the drawer (470 pt) plus the chart was not checked.
