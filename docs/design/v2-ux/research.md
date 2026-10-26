# Glidepath v2 UX: research and rulebook

Scope: structure, information architecture, interaction and clarity. The visual style (dark glass, silver, one amber accent) stays.
Written 2026-10-26. No source code was changed.

How this was built: Apple HIG text was read from Apple's own JSON feed behind each HIG page
(`developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`), because the HTML pages render with
JavaScript and plain fetches return only a title. NN/g, Laws of UX, calmtech.com and vendor docs were fetched directly.
Section 5 lists what could **not** be verified. Where a rule rests on a secondary source, the Source column says so.

Glidepath today (read from `Sources/Glidepath`, skimmed, not audited): menu bar glyph with five states (`MenuBarLabel.swift`:
idle, running(n), changesWaiting(n), paused, failed), a popover of PR cards (`Popover.swift`, 796 lines), a main window
with five sidebar sections Now / History / Repos / Schedule / Settings (`WindowRoot.swift`), a run-detail "Flight recorder"
(`FlightRecorder.swift`, 1200 lines), and a ~1,400-line onboarding. Settings has sections including Look, Menu bar,
Notifications, Reviewing, Budget, Advanced.

---

## 1. Rulebook (50 rules)

Each rule is testable: you can look at a screen and answer yes or no. Source URLs are in section 6; the short tag in the
Source column maps to them.

### A. Status at a glance ("is it working? what needs me?")

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 1 | The first line of every surface answers "is it working?" and "what needs me?" in words, before anything else. | Nielsen #1; NN/g dashboards ("focused on a single task: communicating critical information") | Popover header and Now page header are one sentence: "All clear · next sweep 5:00 PM" or "2 reviews need you". |
| 2 | The menu bar label carries one glyph plus at most one number, and the number means "needs you", never "activity". | HIG menu bar extras; Calm Tech #1, #3; Dropbox icon table (states, no dedicated error icon) | Keep the count only for `changesWaiting`. A running sweep shows motion or progress, not a count. |
| 3 | Never encode state by colour alone. Use glyph shape, position or a word as well. | HIG Color ("avoid relying solely on color"); NN/g dashboards | Failed and paused need distinct silhouettes in the template-image glyph; amber alone is not a state. |
| 4 | Every state has a plain-word name and, when it can be changed, a verb next to it. | Nielsen #1, #9; Dropbox "Syncing paused → Resume" | "Paused until 9:00 · Resume", not a bare pause glyph. |
| 5 | Match interruption to importance. Status is passive and visible on demand; only decisions and breakage may interrupt. | HIG Feedback; HIG Managing notifications ("accurately represent urgency"); NN/g indicators vs notifications | Run finished with nothing for you: no notification. Review needs you: one notification. Auth broke: persistent banner plus one notification. |
| 6 | Work when something fails: show the last good result with a visible, non-blocking label of the problem. | Calm Tech #6; HIG Alerts ("show cached data and a nonintrusive label") | If `gh` auth expires, the popover still shows last sweep's cards under a "Can't reach GitHub · Fix" banner. |
| 7 | Always show "last run" and "next run" in the same place on every surface. | Nielsen #1 | One footer/subtitle pattern: "Last sweep 9:02 · next 5:00 PM". |
| 8 | Feedback within about 400 ms. Anything longer shows motion or determinate progress, never a frozen control. | Doherty Threshold; HIG Progress indicators ("use determinate when possible", "keep moving") | Run now shows "Starting…" at once, then "Reviewing 2 of 5 PRs". |
| 9 | Don't rely on the menu bar item being visible. Offer another way in and let people choose to show it. | HIG Menu bar extras ("avoid relying on the presence of menu bar extras"; Dock menu; opt-in at setup) | Dock menu and app menu carry Open, Pause, Run now. Onboarding asks whether to show the menu bar icon. |

### B. Inbox and triage of AI findings

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 10 | One queue for "needs a human decision", sorted by urgency. Everything else is history and lives elsewhere. | Graphite PR inbox sections; Sentry For Review; Linear Triage ("excluded from all views by default") | Now's top list = reviews held for you plus failures. Posted, skipped and approved-with-nothing go to a collapsed "Done" group or History. |
| 11 | An item row is readable in one pass, top-left to bottom-right: what (PR title), who, verdict, and the one-line reason. | HIG Layout (reading order); Refactoring UI (secondary) | Card: repo/#PR + title, avatar + author, verdict chip, reason sentence. Nothing else until opened. |
| 12 | One primary action per item, in a fixed place. Everything else sits in a menu or secondary gesture. | HIG Toolbars (one prominent action, trailing); HIG Alerts (default on trailing side); Raycast Action Panel (Enter = primary, ⌘K = the rest) | Primary: Post (hold). Secondary under "…" or ⌘K: Open PR, Discard, Snooze, Copy review. |
| 13 | Make discard undoable instead of confirmed. | HIG Alerts ("avoid alerts for common, undoable actions"); NN/g confirmation vs undo ("undo is preferred"); HIG Undo and redo | Swipe-discard shows "Discarded · Undo" for ~8 s and lands in History > Discarded. No dialog. |
| 14 | Keep friction only where the action is outward-facing and irreversible, and name the consequence on the control. | NN/g confirmation dialogs (be specific, name the outcome, no generic "Are you sure?"); HIG Alerts (specific verb titles) | Hold-to-post stays for posting to GitHub. Its label says what happens: "Hold to post review on #482 as you". |
| 15 | Offer "Later" as well as "Discard". | Linear snooze (`H`), Sentry archive-until-escalates | Snooze a held review until the PR's head changes or tomorrow. |
| 16 | Findings carry a short fixed severity vocabulary (3 levels), consistent everywhere. | CodeRabbit (5 severities plus category badge on each comment) | Blocker / Should fix / Nit. Verified-by-checker is a mark on the finding, not a fourth level. |
| 17 | Anything held back stays visible with its reason. Hidden-without-explanation is a bug. | Renovate dashboard ("fully see what's pending… instead of updates being totally invisible") | Skipped PRs (draft, too large, already reviewed, not a collaborator) are listed with the exact reason, collapsed by default. |
| 18 | Keyboard: list navigation, primary action and discard all work without a mouse. | Linear Inbox (`J`/`K`, `U`, `H`, Backspace); HIG Undo (⌘Z) | `J`/`K` move, Return opens, hold Space or ⌘Return posts, ⌘Z undoes the last discard. |
| 19 | A queue empties to good news with the next time, not a blank pane. | HIG Writing ("clear next steps on blank screens"); NN/g empty states | "Nothing needs you. Next sweep 5:00 PM." plus Run now. |

### C. Schedule editing

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 20 | Show the outcome in a plain sentence first and the editor second. | Nielsen #1, #6; NN/g recognition vs recall | Top of Schedule: "Weekdays at 9:00 and 17:00. Next: today 5:00 PM." |
| 21 | Offer presets before the custom editor. | Hick's Law; HIG Settings (best default for most people); NN/g progressive disclosure | Presets: Workday (9, 13, 17) / Hourly in work hours / Once a day / Custom. |
| 22 | Use a conventional control first. A novel control may be a power view but must not be the only path. | Jakob's Law; Nielsen #4 | The 24-hour dial is a visualisation and "Custom" editor. Time chips and day toggles must reach every setting the dial can. |
| 23 | Edits apply live and show their effect (new next-run time) immediately. | Nielsen #1; HIG Undo ("show the results") | No Save button. Changing a time updates the sentence and the next-run time at once, with Undo. |
| 24 | Pause is one tap from the status surface, shows when it ends, and ends itself. | Nielsen #3; HIG Popovers ("a few related tasks") | Popover header: Pause > 1 hour / until tomorrow. Label "Paused until 9:00". |

### D. Run history and logs for non-experts

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 25 | Run history has three layers: outcome sentence, per-PR results, raw log. No more than two taps from list to raw log. | NN/g progressive disclosure (two levels practical maximum); GitHub Actions (run summary > job graph > log) | History row > run detail (per-PR) > "Show log". Flight recorder becomes the log layer, not a page. |
| 26 | A run row reads as a result in plain words, with one status icon in a fixed position. | GitHub Actions (status icon left of each job); Vercel deployments list | "Reviewed 3 · 1 needs you · 2 approved · 4 skipped", time, icon at left. |
| 27 | Raw logs, transcripts and file paths are behind one labelled control and never the default. | NN/g progressive disclosure; Nielsen #8; Nielsen #2 (no jargon) | A single "Show log" button; transcript tool calls are hidden until expanded. |
| 28 | One vocabulary, used everywhere. | Nielsen #2, #4; HIG Windows ("use the term window") | The code uses "sweep" (sidebar footer), README says "run", the detail view says "Flight recorder". Pick **run** or **sweep** and one name for the detail view. |
| 29 | Skips and failures use a closed list of reasons, each with a human sentence. | Renovate; NN/g error messages (specific problem) | Map the reasons the README lists (draft, bot, too many lines, already reviewed, outside allowed authors) to short fixed phrases. |

### E. Errors with a next action

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 30 | Every error says what happened, to what, and how to fix it, and the fix is a button where possible. | Nielsen #9; NN/g error-message guidelines; HIG Writing ("be clear about what someone can do to fix it") | "GitHub login expired for owner/repo. [Sign in again]" which runs the fix or opens Terminal with the command. |
| 31 | Put the error at the thing it concerns and roll up one summary to the status surface. | NN/g error messages ("place near the element"); HIG Feedback | A repo row shows its own failure. The popover shows "1 repo can't be reached" linking to it. |
| 32 | Errors persist until fixed or dismissed. They never auto-dismiss. | NN/g indicators ("don't use auto-fading toasts for errors") | Failure banner stays; the glyph stays `failed` until the next success. |
| 33 | Sort errors into three classes with different weight: "you can fix it", "we'll retry", "tell us". | Calm Tech #6; HIG Feedback (match delivery to significance) | Auth/tool missing = banner + fix button. Network blip = quiet "will retry at 9:30". Bug = "Copy diagnostics". |
| 34 | Alerts are for decisions that block, never for information, never at launch. | HIG Alerts ("use sparingly", "avoid showing an alert when your app starts") | No launch-time dialogs. Update available is an indicator, not a modal. |
| 35 | Don't repeat yourself: one notification per event, grouped per run. | HIG Notifications ("avoid multiple notifications for the same thing") | One "3 reviews ready" per run, not one per PR. |
| 36 | Prevent errors where you can: check preconditions on entry, not on failure. | Nielsen #5; HIG Settings ("avoid asking for setup info you can get another way") | Tool and login health is checked at launch and shown as a single "Health: OK / needs attention" row. |

### F. Settings and defaults

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 37 | Minimise the number of settings. Decide for the user and keep the decision overridable only if someone will ask. | HIG Settings ("minimize the number of settings"); Tesler's Law (absorb complexity in the design) | Remove or hide any setting nobody asked for. New defaults only via setup writers (project rule). |
| 38 | Task-specific options live where the task is, not in Settings. | HIG Settings ("task-specific options") | Posting mode per repo goes in the Repos row. Schedule is on Schedule. Pause is in the popover. |
| 39 | Use a standard Settings window: ⌘, opens it; panes chosen from a stable toolbar; title shows the active pane; last pane restored. | HIG Settings (macOS) | Move Settings out of the sidebar into a real Settings window (`Settings` scene) with 3 panes. |
| 40 | One "Advanced" disclosure, two levels maximum, labelled with what's inside. | NN/g progressive disclosure | "Advanced: config file, logs, reset state, signal colour". Nothing under Advanced that a first-week user needs. |
| 41 | Describe what a setting does when it is on. Don't write "Enable X". | HIG Writing (settings labels) | "Post automatically. Reviews go to GitHub as soon as they pass the check." |
| 42 | The raw file is an escape hatch, labelled as such. | Nielsen #7 (expert accelerators hidden from novices) | "Edit config.toml" under Advanced only. |
| 43 | Risky settings need a deliberate step and a plain-language consequence. | NN/g confirmation dialogs ("require a nonstandard step for the most dangerous"); HIG Alerts | Switching a repo from draft to auto-post uses hold-to-confirm and states "Reviews will post as you without asking." |

### G. Navigation, windows, hierarchy

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 44 | Sidebar: at most five top-level items, never more than two levels, labels are nouns of the user's job, sidebar visible by default and hideable. | HIG Sidebars; Miller's Law; Hick's Law | Four destinations (section 3). No third level; detail panes replace the content pane. |
| 45 | A window title names the current page, under about 15 characters, and never the app name. Each page has one job and at most one primary toolbar action on the trailing side. | HIG Toolbars; Nielsen #8 | Titles: Now, History, Repos, Schedule. Primary action: "Run now" on Now only. |
| 46 | Never put critical information or actions at the bottom of a window or sidebar. | HIG Windows, Layout, Sidebars (all three say it) | The "Next sweep" footer in the sidebar is the only status the sidebar shows; move it to the page header too. |

### H. Hierarchy, type, colour, onboarding (apply to every screen)

| # | Rule | Source | Glidepath application |
|---|------|--------|-----------------------|
| 47 | Use at most three text levels per screen (title, body, secondary), built from weight and colour as well as size. Respect macOS type: 13 pt body, 10 pt absolute minimum, no Light or Thin weights. | NN/g visual design (about three sizes); HIG Typography (macOS built-in styles; "avoid light font weights"; "adjust weight, size and color"); Refactoring UI (secondary) | Fix one ladder, e.g. 15 semibold / 13 regular / 11 secondary, and ban other sizes. Audit 10–11 pt secondary text on glass for contrast. |
| 48 | Spend the accent colour on one meaning only. | Von Restorff Effect; HIG Color ("avoid using the same color to mean different things") | Amber = "needs you now". Brand marks, selection and hover are silver. |
| 49 | Group by proximity and spacing, not boxes inside boxes, and keep glass for the control layer with quieter material under content. | NN/g visual design (Gestalt); HIG Layout (negative space, separators); HIG Materials ("don't use Liquid Glass in the content layer", "use sparingly") | Sidebar and toolbar carry the glass. A card holds one item and separates its parts with spacing and weight, so the verdict is the first thing the eye finds. |
| 50 | Onboarding is fast, skippable and shown once. Ask for nothing you can detect and postpone nonessential setup to where it is used. | HIG Onboarding ("postpone nonessential setup", "context-specific tips"); HIG Settings; NN/g recognition vs recall | Detect `claude`, `gh` and repos. Ask only: which repos, show menu bar icon, then a dry run. Rules, budget and notifications arrive later through a "Finish setup" card on Now. |

Also keep in mind (not numbered): tooltips of 60–75 characters on every icon-only control (HIG Offering help), and about
12 pt of padding around bezeled hit targets and 24 pt around unbezeled ones (HIG Accessibility, Fitts's Law), with the
Post target in the same corner of every card.

---

## 2. Pattern library (teardowns)

Confidence: **verified** means the pattern is stated in the page fetched; **inferred** means my reading of the
product's documented behaviour.

### Menu bar and utility apps

- **Dropbox sync icons** (verified, `help.dropbox.com/sync/macos-sync-icons`). The whole account is one icon with a small
  set of states: fully synced, sync in progress, paused, not connected, unread count. There is no dedicated error icon.
  Why it works: a few states people can name, one place to look. Maps to rules 2–4: reduce Glidepath's glyph states to
  *quiet / working / needs you / attention*, each with a verb on click.
- **iStat Menus** (verified, `bjango.com/mac/istatmenus`). A headline value in the bar and layered detail in the dropdown;
  a "combined" mode merges items to save space; Rules fire on a threshold held for a duration (CPU above 60% for 10 s).
  Maps to rules 2, 5: the bar shows one number; detail waits in the popover; notify only when a condition persists
  (for example, three failed sweeps in a row), not on one blip.
- **Ice** (verified, `github.com/jordanbaird/Ice`). Hidden and always-hidden sections, reveal on demand, and features
  grouped into four categories (item management, appearance, hotkeys, other). Maps to rules 38–40: default quiet,
  reveal on demand, and group a long settings list into four labelled areas at most.
- **CleanShot X Quick Access Overlay** (verified, `cleanshot.com/features`). After the event, a small card in a corner
  offers the few actions that matter (copy, save, annotate, upload, drag out) and closes itself on a timer you
  can configure. Maps to rule 12 and the notification: "3 reviews ready" with Open and Post-all, auto-dismiss only
  when nothing needs a decision.
- **Raycast Action Panel** (verified, `manual.raycast.com/action-panel`). Return runs the primary action; ⌘K lists every
  action for the selected item, each with its shortcut, filterable by typing. Maps to rule 12: a card's primary action is
  Return, everything else is ⌘K or "…".
- **Little Snitch connection alert** (verified, `help.obdev.at/littlesnitch6/alert-overview`). Answering an alert
  creates a rule so it does not ask again; the rule's lifetime is chosen at that moment (once, until quit, forever;
  per the rules docs, also at logout, restart or after a period); the alert can be minimised to decide later.
  Why it works: each decision teaches the system, so interruptions fall over time. Maps to posting trust: "Post this one"
  vs "Always post for this repo", and a "Later" that parks the item (rule 15). This is a better path from draft to
  auto-post than a settings toggle (rule 43).

### Background automation and agent dashboards

- **GitHub Actions run page** (verified, `docs.github.com/.../use-the-visualization-graph`). Run summary, then a live
  graph of jobs with a status icon left of each name, then a click into one job's log. Maps to rule 25: outcome, then
  per-PR results (with status icons), then log.
- **Vercel deployments** (verified, `vercel.com/docs/deployments/overview`). Project overview shows the latest
  production deployment with commit details and logs for debugging; the deployments list has row actions (Redeploy,
  Inspect, Promote). Maps to Now: latest run result first, row actions on each result.
- **Linear Inbox and Triage** (verified, `linear.app/docs/inbox`, `/triage`). Inbox: Priority tab that separates
  attention-needed from the rest, snooze (`H`), mark read (`U`), keyboard navigation (`J`/`K`), a hard cap of 2,000
  notifications. Triage: Accept (`1`), Decline (`2`), Duplicate (`3`), Snooze (`H`); unreviewed items are excluded
  from all other views by default. Maps to rules 10, 13, 15, 18: the needs-you queue is separate, numbered or
  lettered shortcuts act on it, and a decline is a state, not a deletion.
- **Sentry issues** (verified, `docs.sentry.io/product/issues/states-triage/`). Explicit states (New, Ongoing, Escalating,
  Regressed, Archived, Resolved); a For Review filter; Archive "until it escalates"; resolve "in the next release".
  Maps to rules 15, 17: a PR you chose not to post for is **Seen**; it returns to the queue only if its head changes
  (the same idea as "regressed").
- **Renovate Dependency Dashboard** (verified, `docs.renovatebot.com/key-concepts/dashboard/`). One issue lists everything
  pending, including updates waiting for approval, so nothing is invisible; ticking a checkbox triggers the action.
  Maps to rule 17 and the Now page: one list of everything held, each with its reason and one-click release.
- **Graphite PR inbox** (verified, `graphite.com/docs/use-pr-inbox`). Six default sections (Needs your review, Approved,
  Returned to you, Merging and recently merged, Drafts, Waiting for review), user-editable and shareable sections, ⌘K
  search. Maps to Now grouping: *Needs you*, *Your PRs (autopilot)*, *Posted*, *Skipped*, same card anatomy in each.
- **CodeRabbit** (verified, `docs.coderabbit.ai/guides/code-review-overview`). A walkthrough summary at the top of
  each PR, each comment starting with a category badge and a severity (Critical, Major, Minor, Trivial, Info), one-click
  apply, and `pause`/`resume` commands. Maps to rules 11, 16: a review opens with its summary and verdict, findings carry
  one severity, and Pause is a first-class command.

### Settings design

- **HIG Settings** (verified): few settings, strong defaults, task options in place, a toolbar-pane Settings window,
  ⌘, to open, restore last pane. This is the base for rules 37–42.
- **Ice and iStat** (above): four-category grouping; density controls are the only power knobs most people touch.
- Things 3, Arc, Linear settings and macOS System Settings were **not** fetched; see section 5.

---

## 3. Recommended information architecture

### Menu bar label

- Glyph states, four, each distinguishable without colour: **quiet** (idle or last run clean), **working** (a run is
  in progress, animated or with progress), **needs you** (glyph + count of items awaiting a decision), **attention**
  (paused or failed; different silhouettes; the click target shows the reason).
- Template image, no colour. The update dot stays. No number for activity.
- Right-click or secondary click: a native menu (HIG prefers a menu to a popover for simple things): Pause / Resume,
  Run now, Open Glidepath, Settings…, Quit. Left click opens the popover.

### Popover (about 360 pt wide, nonmodal)

HIG allows a popover here because the content is richer than a menu (cards with hold-to-post and swipe). Keep it to
"a few related tasks".

1. Header: one status sentence (rule 1) and the Pause control (rule 24).
2. If something is broken: one banner with a Fix button, above the list (rule 30).
3. Body: the needs-you queue, at most five cards, same anatomy as the window, then "N more in the window".
4. Footer: "Last sweep … · next …" (rule 7), Run now, Open window.

Not in the popover: settings, schedule editing, history, logs, repo management. No second popover or sheet over it.

### Main window (sidebar with four destinations)

| Page | Single job | Contains | Primary action |
|------|-----------|----------|----------------|
| **Now** | Decide what needs you | Status header; needs-you queue (reviews held; failures); "Your PRs" (autopilot) as a second group with the same card; live run progress; collapsed "Done today" and "Skipped (reason)" | Run now |
| **History** | Look back, trust the result | Run list; run detail = outcome sentence > per-PR results > "Show log" (the current Flight recorder lives here as the log layer) | none |
| **Repos** | Choose what's watched | Repo list; per-repo posting mode and rules file inline; add repo | Add repo |
| **Schedule** | Say when | Plain-language summary; presets; Custom editor (the dial) | none (edits are live) |

### Settings (separate window, ⌘,, three panes)

- **General**: launch at login, show menu bar icon, notifications (one switch per kind), appearance (signal colour).
- **Reviewing**: model, PRs per sweep, size limits, budget, rules default, own-PR tending default.
- **Advanced**: config file, state folder, log, reset, "Fix all in Terminal" and tool health.

### Cut, merge, hide (candidates, check against the code before acting)

- **Cut as a sidebar page:** Settings. It becomes a window (rule 39).
- **Merge:** Flight recorder into History run detail (rules 25, 27). "Reviews" and "History" are one thing under one name.
- **Merge:** sidebar-footer "Next sweep" and the page header status into one component used everywhere (rule 7, 46).
- **Hide behind Advanced:** config.toml, state folder, log, reset, signal colour, the shortcuts sheet's long list (keep a
  short "Keyboard" help).
- **Move to where the task is:** posting mode (to Repos), pause (to popover), "Check again/Fix" (to a single Health row).
- **Decide:** the Look and Menu bar settings. If they have defaults nobody changes, cut them (rule 37).

---

## 4. Anti-patterns to avoid

1. A dashboard that is a pile of equal-weight boxes: no first read. (NN/g visual hierarchy; Von Restorff)
2. Two names for one thing (sweep / run / flight recorder). (Nielsen #2, #4)
3. Status shown only by colour or by an unlabelled glyph. (HIG Color)
4. A number on the menu bar icon for activity instead of attention. (Calm Tech #2, #3)
5. Confirm dialogs for reversible actions ("Discard this review? OK / Cancel"). (NN/g, HIG Alerts)
6. Generic errors ("Something went wrong", "Error 1"), or an error that names the problem but not the fix.
   (NN/g, HIG Alerts: avoid titles like "Error")
7. Auto-dismissing toasts for failures. (NN/g indicators)
8. Alerts or banners on launch for information. (HIG Alerts)
9. Hidden-without-reason: items that vanish when filtered or skipped. (Renovate pattern, Nielsen #1)
10. Settings pages as a junk drawer: every option exposed, none with a default story. (HIG Settings, Tesler's Law used
    as an excuse: complexity must be absorbed by the design, not moved to Settings)
11. A control that exists only in one place (a dial with no alternative, a gesture with no menu equivalent).
    (Jakob's Law, HIG Menu bar: always show the same set of items)
12. Nested containers, nested popovers, nested navigation beyond two levels. (HIG Popovers, Sidebars; NN/g)
13. Logs, paths and raw JSON as default content for non-experts. (Nielsen #2, #8)
14. A tour or tutorial before first use; asking for setup that can be detected. (HIG Onboarding)
15. Using glass or accent colour on content as well as controls, so nothing stands out. (HIG Materials; Von Restorff)
16. Text under about 11 pt or low contrast on translucent surfaces. (HIG Typography, Accessibility)
17. Critical status in the bottom edge of a window. (HIG Windows, Layout, Sidebars)

### Review checklist (use on every screen before shipping)

1. Can I say the screen's one job and its one primary action in a sentence?
2. Does the top line say whether it is working and what needs me?
3. Is anything held back visible with a reason?
4. Does every error carry a fix?
5. Is every destructive action undoable, or its confirmation specific and rare?
6. Count text sizes (≤3), accent uses (one meaning), nesting levels (≤2).
7. Does any setting exist that could have a default?
8. Is the same thing called the same name here as in the popover and README?

---

## 5. What could not be verified (do not cite)

- Not fetched or blocked: Tailscale macOS menu behaviour (docs pages did not describe the menu), 1Password mini (403),
  Backblaze (no results), Things 3, Arc, Linear's settings screens, macOS System Settings, and Vercel's status labels.
  Nothing in sections 1–4 depends on them.
- Little Snitch "silent mode" details were not on the pages fetched. Only alert mode and rule lifetimes are cited. The
  list of expiry options (logout, restart, after a period) comes from a search snippet of
  `developer.obdev.at/littlesnitch6/concepts-rules`, not the page.
- **Refactoring UI**: the authors' Medium post returned 403. The points used (size is not everything; de-emphasise
  rather than emphasise; labels last) come from secondary summaries, so treat them as paraphrase. The palette page
  on refactoringui.com was fetched but is about colour scales and was not used.
- **Don Norman**: only secondary summaries were found for affordance/signifier/mapping/feedback. NN/g's article on the
  gulfs of execution and evaluation (fetched) is the primary support for "make state perceivable and interpretable".
  Norman's own text was not read.
- GitHub Actions re-run and annotations, and the Renovate dashboard section names, were not confirmed.
- HIG has no empty-state page at the time of writing; empty-state guidance comes from HIG Writing and NN/g.
- Whether the macOS 26 system chrome will restyle Glidepath's custom sidebar was not tested. HIG says standard
  components pick up Liquid Glass automatically and custom use should be sparing; check on a macOS 26 machine.
- The Glidepath code was skimmed only for section names and glyph states. Cuts in section 3 are candidates, not audited.

---

## 6. Sources

Apple HIG (base `https://developer.apple.com/design/human-interface-guidelines/`):
[the-menu-bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) (includes Menu bar extras),
[popovers](https://developer.apple.com/design/human-interface-guidelines/popovers),
[sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars),
[settings](https://developer.apple.com/design/human-interface-guidelines/settings),
[onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding),
[alerts](https://developer.apple.com/design/human-interface-guidelines/alerts),
[windows](https://developer.apple.com/design/human-interface-guidelines/windows),
[toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
[notifications](https://developer.apple.com/design/human-interface-guidelines/notifications),
[managing-notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications),
[undo-and-redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo),
[typography](https://developer.apple.com/design/human-interface-guidelines/typography),
[layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[loading](https://developer.apple.com/design/human-interface-guidelines/loading),
[feedback](https://developer.apple.com/design/human-interface-guidelines/feedback),
[progress-indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators),
[materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[color](https://developer.apple.com/design/human-interface-guidelines/color),
[accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
[writing](https://developer.apple.com/design/human-interface-guidelines/writing),
[offering-help](https://developer.apple.com/design/human-interface-guidelines/offering-help),
[menus](https://developer.apple.com/design/human-interface-guidelines/menus).

Classic principles:
[Nielsen's 10 heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/),
[progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/),
[recognition and recall](https://www.nngroup.com/articles/recognition-and-recall/),
[empty states](https://www.nngroup.com/articles/empty-state-interface-design/),
[error messages](https://www.nngroup.com/articles/error-message-guidelines/),
[confirmation dialogs](https://www.nngroup.com/articles/confirmation-dialog/),
[indicators, validations, notifications](https://www.nngroup.com/articles/indicators-validations-notifications/),
[dashboards and preattentive attributes](https://www.nngroup.com/articles/dashboards-preattentive/),
[principles of visual design](https://www.nngroup.com/articles/principles-visual-design/),
[the two UX gulfs](https://www.nngroup.com/articles/two-ux-gulfs-evaluation-execution/),
[Laws of UX](https://lawsofux.com/) ([Hick](https://lawsofux.com/hicks-law/), [Miller](https://lawsofux.com/millers-law/),
[Jakob](https://lawsofux.com/jakobs-law/), [Tesler](https://lawsofux.com/teslers-law/),
[Fitts](https://lawsofux.com/fittss-law/), [Doherty](https://lawsofux.com/doherty-threshold/),
[Von Restorff](https://lawsofux.com/von-restorff-effect/),
[Aesthetic-usability](https://lawsofux.com/aesthetic-usability-effect/)),
[Calm Technology principles](https://calmtech.com/),
[Refactoring UI tips (secondary)](https://medium.com/refactoring-ui/7-practical-tips-for-cheating-at-design-40c736799886).

Teardowns:
[Dropbox sync icons](https://help.dropbox.com/sync/macos-sync-icons),
[iStat Menus](https://bjango.com/mac/istatmenus/),
[Ice](https://github.com/jordanbaird/Ice),
[CleanShot X features](https://cleanshot.com/features),
[Raycast Action Panel](https://manual.raycast.com/action-panel),
[Little Snitch connection alert](https://help.obdev.at/littlesnitch6/alert-overview),
[GitHub Actions visualization graph](https://docs.github.com/en/actions/how-tos/monitor-workflows/use-the-visualization-graph),
[Vercel deployments](https://vercel.com/docs/deployments/overview),
[Linear Inbox](https://linear.app/docs/inbox), [Linear Triage](https://linear.app/docs/triage),
[Sentry issue states and triage](https://docs.sentry.io/product/issues/states-triage/),
[Renovate Dependency Dashboard](https://docs.renovatebot.com/key-concepts/dashboard/),
[Graphite PR inbox](https://graphite.com/docs/use-pr-inbox),
[CodeRabbit review overview](https://docs.coderabbit.ai/guides/code-review-overview).
