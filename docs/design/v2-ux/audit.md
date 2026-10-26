# Glidepath UX audit (v1.5.0, as built)

Scope: structure, flows, density, wording and affordances. Colour, glass and the Gotham look are out of scope and not criticised.
Method: stock snapshotter (`glidepath --snapshot`, fixtures only, nothing read from the live config or state) plus a throwaway copy of the source in `/tmp` that renders the surfaces the snapshotter skips. The repo source was not changed. All PNGs are in `docs/design/v2-ux/screens/`. Every claim below comes from a screenshot or from the code at the cited line.

Screenshot names: `popover-*` = menu bar popover states, `menubar` = glyph states, `win-*` = main window pages and onboarding steps, `sheet-*` = the PR detail sheet, `extra-*` = renders from the scratch copy (full-length Settings/History/Now, repo settings sheet, add-repo, review-now).

---

## 1. Navigation map

```
Menu bar glyph (menubar.png)
  click or ⌥⌘G ........ Popover (popover-*.png)
        run/stop button ..... starts a sweep (tap) / stops it (HOLD 0.9 s) / resumes if paused / opens onboarding if no repos
        window button ....... Main window (last section)
        card (click) ........ expands in place: Open on GitHub, or Hold to post + Discard
        "Open" (digest) ..... Main window > Now
        ellipsis menu ....... Open Glidepath · Update/version · Pause/Resume · Open log · History · Check for updates · Last run tokens · Open at login · Quit

Main window (opens by itself on launch when there is no config)
  Onboarding (no sidebar): Welcome > Your tools > Repos > How to review > Schedule > First sweep
  Sidebar: Now · History · Repos · Schedule · Settings      (⌘1..⌘5)
    Now ......... Review… menu (Sweep all repos now · Review PRs… · Review someone's PRs…)
                  Needs you rows (Discard, Hold to post, row click > PR sheet, "Review anyway" for too-large)
                  Recent: 3 run cards > row click > PR sheet; folds: "N already reviewed", "N skipped"; Stop
    History ..... all run cards by day > row click > PR sheet
    Repos ....... Add repo (sheet) · per row: draft control (Default/On/Off) · row click > repo settings sheet
                  repo sheet: Review now · How reviews post · Whose PRs · Review rules · Code graph · Flagged paths · Remove repo… (alert)
    Schedule .... Running/Pause 1 h/Until tomorrow · dial · presets · days · upcoming timeline
    Settings .... search · 6 anchor chips · 30 rows · config.toml drawer
  Sheets: PR sheet (860×760), Review now (PR / author), Add repos, Keyboard shortcuts (⌘/, 54 shortcuts)
  Alerts (AppKit): Run now · Review now · Stop · Discard · Post · Review anyway · Remove repo · Update · reset/uninstall
  Menu bar menus: Glidepath · File · Edit · View · Sweep · Review · Window · Help
```

Depth to anything that is not the glance: popover 1 click, window 2, a PR's detail 3 (popover > Open > row), a repo setting 3 (sidebar > row > scroll in a sheet), remove a repo 4+ (see §4).

---

## 2. Inventory per surface

"Controls" = things that react to a click, hold, drag or key. Font sizes and weights are the ones used by that file (grep of `.font(.system(size:))`). App-wide there are **18 distinct point sizes (8.5 to 28) and 5 weights**; 12 pt is used 92 times and 13 pt 52 times, so most of the interface lives in a 1 pt band.

| Surface | Purpose | Controls | Text elements | Badges / marks | Sizes / weights | Primary action |
|---|---|---|---|---|---|---|
| Menu bar glyph | Status at a glance | 1 (toggle popover) | 0 to 1 (count) | 6 states: idle, running+n, changes+n, paused, failed, update dot | n/a | Open popover |
| Popover (drafts state) | Triage | run/stop, window, ≤N cards, "Open", ellipsis + 9 menu items + 1 toggle = about 15 targets; per expanded card 2 more | 3 stat labels, caption, per-card name + state, digest title + sentence, "Open" | 3 numerals, per-card state dot + word, update line | 5 sizes (12, 13, 15, 26 numerals, 9.5 caps), 3 weights | Not stated; the run button is the biggest thing, but the job is "post or discard" |
| Now | What needs me, what happened | Review… menu (3 items), per held row 2 (+ row click), per run card Stop, rows, 2 folds, sidebar 5 | title, status line, 2 cap labels, per run: title, meta, sentence, rows (title + verdict + reason + repo#n + state) | needs-count in sidebar and header, verdict words, 4-dash stage meter, state words | 28, 16, 13, 12, 11, 9.5; bold/semibold/medium | Hold to post (when something is held), otherwise none |
| History | Archive | run cards, rows, folds | same as Now, plus day headings | same | same | None (no search, no filter) |
| Repos | Manage repos | Add repo, per repo: row (opens sheet) + 3-way draft control | slug, "Draft PRs" label, dots | one dot per PR of the last run | 28, 14, 12.5, 12 | Add repo |
| Repo sheet (720×640) | Per-repo rules | Review now, Done, 3-way posting, 3-way authors (+login editor), rules field + Edit + Replace/Extend, toggle, flagged paths (chips, Add path, note), Remove repo… = about 14 | 6 row titles + 6 captions + 1 preview | none | 8 sizes in `Repos.swift` | None; 6 equal-weight rows |
| Schedule | When it runs | 3-way pause, 2 dial handles, centre scroll, −/+, 4 presets, 7 day toggles, upcoming timeline (8 times) | title, subtitle, 4 caps, 4 preset labels + captions, 3 stats, 8 times + 8 day labels | marker dots | 8 sizes, 3 weights | None; presets and dial compete |
| Settings | Everything else | search, 6 chips, **30 rows**: 13 toggles, 5 segmented, sliders (strictness, size, glass, budget), icon picker (3), colour picker (4), shortcut recorder, path chips, 4 file buttons, Check now, Check again/Copy, Hold to reset, Uninstall | 30 labels + about 25 captions | none | 8 sizes, 3 weights | None (a scroll column) |
| PR sheet | Read one finding, post | Done, Discard, Post review, Review again, 2 footer links | meta line, 4-stage trajectory (8 labels), verdict bar, final text, session notes, gathered | verdict bar | 5 sizes | Post review (when held) |
| Onboarding | Setup | per step: Back, Continue (+ Check again, Copy, search, 4 to N checkboxes, 3-way ×2, dial, 7 days, 2 end buttons) | 6 steps, rail of 6 labels | step dots | 7 sizes | Continue |
| Shortcuts sheet | Reference | search, Done | 54 shortcuts in groups | none | 3 sizes | None |

### Duplicated functionality

| Thing | Where it lives (count) |
|---|---|
| Next sweep time | Now header, sidebar footer, Schedule subtitle, popover (never; see P5): **3 places in the window, 0 in the popover** |
| Run a sweep now | popover play, Now > Review… > Sweep all repos now, ⌘R, Repo sheet "Review now" (one repo): 4 |
| Stop | popover (hold 0.9 s, no alert), run card "Stop" (click, then alert), ⌘. , Sweep menu: 3 interaction models |
| Post a held review | popover card (hold), Now row (hold), PR sheet (click then alert with preview), ⌘↩: 3 models |
| Pause | popover menu (indefinite toggle), Schedule (Pause 1 h / Until tomorrow / Running), ⇧⌘P |
| Open log | popover failed-state link, popover menu, Settings > Files, ⌥⌘L |
| Update | popover update line, popover menu (2 items), Settings > Updates, app menu |
| Open at login | popover menu, Settings > Menu bar |
| Posting mode | onboarding "How reviews post", Settings "When a review is ready", repo sheet "How reviews post" |
| Authors filter | onboarding "Whose PRs", Settings "Authors", repo sheet "Whose PRs" |
| Dry run | onboarding first sweep, Settings > Advanced > Dry run |
| History | sidebar, popover menu "History", ⌘2. The popover's own "Open" goes to Now, not History |

### Terminology inconsistencies (same thing, different name; or one name, two things)

| Concept | Names in use |
|---|---|
| A scheduled run over all repos | Sweep (cards, menu), Run (a11y label, alert button "Run now", "Run the review pipeline"), "Last run: 412k tokens" (popover menu), "Sweep all repos now" |
| A by-hand run | Review… (menu), Review now (repo sheet, sheet title), Review PRs…, Review again, Review anyway, "Reviewing …" status |
| The window page | **History** in the sidebar, `.reviews` in code, "Reviews" in two user-visible strings (`Repos.swift:19`, onboarding preview "post from Glidepath or Reviews"), `showOverview` for Now in the shortcut table, a top-level **Review** menu that is about PR actions |
| "Draft" | GitHub draft PR (Repos "Draft PRs", Settings "Review draft PRs", digest "1 skipped: 1 draft") **and** a review held for you ("Draft first", "Held as draft", Confirm text "Discard the draft review") |
| Held review | held, waiting for you, Needs you, "Hold for me", "not posted", Held as draft, "Waiting for you to post" |
| Posting modes | Comment / Full review / Draft first (onboarding, repo sheet) **vs** Post review / Comment only / Hold for me (Settings). Config value is `review`; two alerts print `posting = "review"` to the user (`Confirms.swift:14,39`) |
| Verdict | Changes, Changes requested, "need changes", "Changes · 4 findings" |
| Authors filter | Everyone / Collaborators / Only these (Settings) vs Collaborators / Anyone / These people… (onboarding, repo) |
| Flagged paths | "Look closer at" (Settings) vs "Flagged paths" (repo sheet) |
| Pause state | "Running" (the not-paused segment), "Paused", "Resume", "scheduled sweeps skipped" |
| Time format | locale 12 h ("Next sweep 8:00 PM", `HeaderCopy.clock`) vs fixed 24 h ("NEXT 20:00", dial, upcoming list; `Schedule.swift:83`, `DialFormat.clock`). Both appear on the same Schedule screen and in the sidebar beside it |
| Cost | tokens only (popover menu, cards, Budget); no unit a person can price |

---

## 3. User jobs: steps, clicks, confusion

Clicks count distinct deliberate interactions. "Wait" is time with no feedback beyond a spinner or animation.

### (a) First launch to first review posted

| # | Step | Note |
|---|---|---|
| 1 | Window opens by itself (`WindowRouter.openAtLaunchIfUnconfigured`, `WindowRoot.swift:100`) | good |
| 2 | Get started | quiet link "Use my config file" beside it |
| 3 | Continue (Your tools) | blocked until claude, gh, git pass; fix is outside the app (copy a command to a terminal), then Check again |
| 4 | tick at least 1 repo | |
| 5 | Continue | |
| 6 | Continue (How to review) | defaults are fine but unread; 3 sections (posting, whose PRs, rules) |
| 7 | Continue (Schedule) | dial, days; defaults are fine |
| 8 | wait about 3 min | dry run of the first repo only, 3 PRs, posts nothing (`Onboarding.swift:835`, `OnboardingFinish.swift:406,434`) |
| 9 | Turn on the schedule (or Post nothing yet) | both land on Now and the dry run keeps going; copy does not say what "Post nothing yet" does to the schedule |
| 10 to 11 | Popover > play | needed because nothing real has run yet; an alert appears only if a repo posts for real |
| 12 | wait for the sweep | |
| 13 | Now > Needs you > **hold** Hold to post 0.9 s | with "Draft first" nothing posts without it |

About 11 interactions, 2 waits, one non-obvious gesture. **The onboarding ends with a dry run that "would post" reviews; the first real review needs a separate manual run or the next scheduled time.** The first-sweep copy ("Would post 3 reviews to lumen/api as comment") also contradicts the "Draft first" the user just saw selected on the previous step (verify against real data; fixtures may be the cause). Screens: `win-onb-welcome`, `win-onb-tools`, `win-onb-repos`, `win-onb-review`, `win-onb-schedule`, `win-onb-sweep`, `win-onb-sweep-landed`.

### (b) "What is it doing now? Did it review my PRs?"

- Glance: glyph shows running count, changes count, paused or failed (`menubar.png`). Good.
- 1 click: popover. Three numerals (Approved / Changes / Skipped) count the **newest run only** (`Popover.swift:317`), the digest says "3 of 6 reviewed. 1 skipped: 1 draft", the caption says "3 in flight, 4 landed · 2 need changes". Five sets of numbers for one run, three different denominators. Cards show only the author's first name; the PR title appears only after expanding the card.
- Idle and clear (the commonest state): the popover shows no caption and no next-sweep time (`Popover.swift:362-371`, `popover-idle-clear-dark.png`). To see which PRs were reviewed: Open > Now > Recent (3 interactions).
- The popover never lists approved or posted PRs. Only held, in-flight and too-large ones become cards (`Popover.swift:307`).

### (c) Look at a finding; post or discard

- Popover route: click glyph, click card (expands title + repo), **Hold** to post or Discard (alert). The finding itself is not readable here. Reading it = Open > Now > row click > PR sheet: 4 interactions.
- Now route: sidebar Now, row text click opens the sheet; Discard (alert) and Hold to post sit on the row, readable without opening the sheet. A held review can be posted without ever seeing it.
- Sheet route: Post review is a click, then an alert showing the verdict and full body (`FlightRecorder.swift:1153`). This is the safest flow and the only one with a preview, but it is the third way to do the same thing.
- Posting needs a 0.9 s hold (Now, popover), discard needs a click then an alert. Publishing is protected by effort, deleting by confirmation: two systems for one family of actions.

### (d) Add / remove a repo

- Add: Repos > Add repo > pick from a list loaded from GitHub (or type owner/name) > Add N repos: 4 interactions, good. The sheet shows "Add 0 repos" disabled until a pick (`extra-add-repo.png`).
- Remove: Repos > row > repo sheet > scroll to the last of 6 rows > Remove repo… > alert > Remove: 5 interactions. Nothing on the Repos list hints that removal exists (no swipe, no context menu, no chevron on the row). ⌘⌫ works only with a repo selected.
- The Repos list itself offers one setting (Draft PRs: Default (off) / On / Off) and the rest is behind the row.

### (e) Change when it runs

- Sidebar Schedule > click a preset: 2 interactions, saves silently ("Saved" stamp appears in the title row). Custom: drag the dial ends (24 h dial) or scroll the centre to change frequency. The only hint is a 9.5 pt caps caption "DRAG THE ENDS · SCROLL THE CENTRE" (`ScheduleControls.swift:138`).
- Frequency is "scroll the centre" or −/+; it is not shown as an editable number or list. The upcoming list below shows 8 times and has no click targets (`Schedule.swift:171-198`); moving a pin is keyboard-only (`Shortcuts.swift:226`).
- Pause (job f) lives on the same page header.

### (f) Pause or stop everything

- Stop a running sweep: popover run button **hold 0.9 s** (looks like a Stop square; a tap does nothing, `Popover.swift:745`), or Now "Stop" text button (alert), or ⌘. . Three behaviours.
- Pause: popover ellipsis > Pause (indefinite, no confirmation, no persistent banner except the amber caption "Paused · Last sweep …"), or Schedule > Pause 1 h / Until tomorrow. The popover caption for pause is truncated at 360 pt ("scheduled sweeps…", `popover-paused-dark.png`).
- In the paused popover the play button resumes (`Popover.swift:444` `runTap`), it does not run: same glyph, different meaning from idle.

### (g) Find out why a run failed

- Popover failed state: caption "Last sweep failed · The review agent sto…" truncated to one line (`Popover.swift:451-459`), "Open log" link, digest says "Failed. claude exited 1: see the log for details". The "Retrying at …" and "Paused since …" third lines are built by `HeaderCopy` but never drawn (`captionLine` prints only headline and line 2).
- "Open log" opens the raw log file in the default app. In the window a whole-run failure has no log link (only Settings > Advanced > Files and ⌥⌘L); a single stopped PR has a good "Why it stopped" panel with a Review again button (`sheet-noresult.png`), which is the best failure design in the app.
- The failed popover also shows "Nothing needs you" under the red banner.

---

## 4. Problems, ranked

Severity: **S1** blocks or misleads a main job, **S2** costs steps or trust every day, **S3** clutter or polish. "H" = heuristic broken (Nielsen N1..N10, plus named principles).

| # | Sev | Problem | Where (file:line, screenshot) | Heuristic |
|---|---|---|---|---|
| 1 | S1 | **Stop and post depend on hidden holds.** Stop = hold 0.9 s with a play/stop glyph that ignores taps; "Hold to post" is a label that reads as a button. No hint of a hold on the control, tap does nothing, no keyboard path except undiscoverable shortcuts. The same actions elsewhere are click + alert. | `Popover.swift:715-757`; `Now.swift:245`; `Card.swift:251`; `HoldButton.swift:16`; `popover-running-dark.png`, `win-now-dark.png` | Affordance, consistency (N4), visibility of system status (N1), accessibility |
| 2 | S1 | **The popover cannot answer the main status questions.** Idle/clear shows no caption and no next-sweep time; HeaderCopy's third line is built and dropped; failed and paused captions are truncated to one 12 pt line; cards show an author's first name, not the PR. | `Popover.swift:362-371, 451-459, 103-160`; `popover-idle-clear-dark.png`, `popover-failed-dark.png`, `popover-paused-dark.png` | Visibility of system status (N1), recognition vs recall (N6) |
| 3 | S1 | **Too many numbers for one run, none reconciling.** Approved/Changes/Skipped numerals + "N waiting for you" + "3 in flight, 4 landed · 2 need changes" + "3 of 6 reviewed. 1 skipped: 1 draft". "Skipped 1" and "1 draft" collide with the held-draft meaning of draft. | `Popover.swift:317, 395-410`; `Core/RunDigest.swift:94-125`; `popover-running-dark.png` | Hierarchy, density, consistency (N4), match with the real world (N2) |
| 4 | S1 | **Setup ends in a dry run, not a result.** First sweep is a 3-PR dry run of the first repo only; the first real review needs another manual run or the schedule, plus a hold. "Post nothing yet" vs "Turn on the schedule" does not say what each changes. | `OnboardingFinish.swift:227, 323-338, 406, 434`; `win-onb-sweep-dark.png`, `win-onb-sweep-landed-dark.png` | N1, N2, N3 |
| 5 | S2 | **One concept, three vocabularies for posting mode and authors.** Comment/Full review/Draft first vs Post review/Comment only/Hold for me; Everyone/Collaborators/Only these vs Collaborators/Anyone/These people…; "Look closer at" vs "Flagged paths". Alerts print `posting = "review"`. | `Settings.swift:22-60`; `Repos.swift:5-20,340-380`; `Confirms.swift:14,39`; `extra-settings-full.png`, `extra-repo-detail.png` | Consistency (N4), match with real world (N2), recognition (N6) |
| 6 | S2 | **"Draft" means two things; "Reviews", "Overview", "Run", "Sweep", "Review" overlap.** Stale "post from Glidepath or Reviews" in two screens. | `Repos.swift:19`; `RunDigest.swift:94-125`; `Shortcuts.swift:13,184-185`; §2 terminology table | N4, N2 |
| 7 | S2 | **Repos page labels the wrong thing.** The "Draft PRs" caption is followed by one dot per PR of the last run (22 dots on lumen/web), which reads as draft-PR count; the only control is a three-way whose first option is "Default (off)". | `Repos.swift:177, 204-215, 223-247`; `win-repos-dark.png` | N2, N6, hierarchy |
| 8 | S2 | **Remove repo is 5 steps deep and undiscoverable; repo rules live in a 6-row modal.** No row affordance (no chevron, no menu), the repo sheet is 640 pt tall so the destructive row sits at or below the fold. | `Repos.swift:589`, sheet frame `Repos.swift:85`; `extra-repo-detail.png` | Progressive disclosure, affordance, N7 |
| 9 | S2 | **Settings is a 30-row, 6-section scroll with chips that are anchors, not tabs.** The default view shows 9 rows; unrelated jobs sit together (tools check, files, reset, uninstall, update, dry run). Several rows duplicate other places (Open at login, Open log, Updates, Pause at budget). | `Settings.swift:22-60, 78-140`; `extra-settings-full.png` | Hick's law, progressive disclosure, density |
| 10 | S2 | **Three different post flows and two safety models.** Hold (popover), hold (Now), click + preview alert (sheet). Hold protects publishing; a click + alert protects deleting. A held review can be posted without reading it. | `Now.swift:229-258`; `Card.swift:249-257`; `FlightRecorder.swift:760-761, 1153-1162` | Consistency (N4), error prevention (N5) |
| 11 | S2 | **Popover is an inbox, a dashboard, a control panel and a menu at once.** 3 numerals, 2 round buttons, caption, stack of up to N glass cards, digest, update line, ellipsis menu with 9 items. The ellipsis menu is where Pause, Open log, History, updates, login, Quit hide. | `Popover.swift:191-330, 637-690`; all `popover-*.png` | Density, Hick's law, progressive disclosure |
| 12 | S2 | **Needs-you rows are repeated in Recent.** The two held PRs appear twice on the first screen (Needs you and the newest run card) with "held" as the only difference. The sidebar footer and Now header both print the same next-sweep line. | `Now.swift:46-56, 150-175`; `win-now-dark.png` | Density, N8 minimalism |
| 13 | S2 | **Run and review vocabulary hides the primary action.** The one filled button on Now is "Review…" and it opens a menu whose first item is "Sweep all repos now"; the popover calls the same thing "Run now"; the repo sheet calls one-repo run "Review now". | `Now.swift:127-146`; `Popover.swift:753`; `Repos.swift:319`; `win-now-dark.png` | N2, N4, affordance |
| 14 | S2 | **Schedule: two time formats, hidden gestures, no list editing.** 24 h dial and upcoming list vs locale time elsewhere; frequency set by scrolling a ring whose hint is a 9.5 pt caps caption; 4 presets and the dial compete as the primary control. | `Schedule.swift:83`; `ScheduleControls.swift:138`; `Sidebar.swift:65`; `win-schedule-dark.png`, `win-onb-schedule-dark.png` | N2, N6, affordance, density |
| 15 | S2 | **Failure is hard to trace from the window.** A whole-run failure has no "Open log" or "Why" in the window, only a log file in the default editor; the popover banner is truncated and loses the retry line. | `Popover.swift:451-459`; `Settings.swift:572`; `Core/Presentation.swift:174-186` | N9, N1 |
| 16 | S3 | **Hold labels are inconsistent about state.** Rows say "posted", "held" and "not posted"; "not posted" has no action and no explanation (dry run? error? comment-only?). | `RunCard.swift:156-170`; `win-running-dark.png` | N1, N9 |
| 17 | S3 | **Popover cards stack and overlap.** In running and drafts states the cards share borders with no gap, and the expanded card sits over the next. | `Popover/Card.swift`; `popover-running-dark.png`, `popover-running-open-dark.png` | Density, hierarchy |
| 18 | S3 | **Micro-caps labels carry meaning at 9.5 pt.** Section names, stat labels, "DRAG THE ENDS", stage names; low contrast and tracking at 1.9 pt. 18 point sizes in total; no clear scale. | `Gotham.swift:34-39`; `Now.swift:289-295`; all `win-*.png` | Hierarchy, legibility (HIG) |
| 19 | S3 | **Onboarding rail uses 37 % of the width for 6 labels and a diagonal line; Schedule step crowds "DAYS" under the −/+ buttons; welcome hero art and first-sweep art take about 25 % of the screen.** | `Onboarding.swift` layout; `win-onb-*.png` | Density, N8 |
| 20 | S3 | **Shortcut surface is 54 entries in 8 menus** including pin nudges, find, selection; the ⌘/ sheet is the only discovery route. | `Shortcuts.swift:1-60,163-260`; `win-shortcuts-dark.png` | Recognition vs recall |
| 21 | S3 | **Alerts print config syntax and internals** ("posting = \"review\"", "the review pipeline", "claude exited 1"). `Presentation.plainFailure` turns "claude exited 1" into a sentence but only the header uses it (`Presentation.swift:74`); the digest line uses the raw text (`RunDigest.swift:59-63`). | `Confirms.swift:14,39`; `RunDigest.swift:59-63`; `popover-failed-dark.png` | N2 |
| 22 | S3 | **System blue and green leak into a silver + amber UI** (links "Cancel", "Add path…", "Replace the built-in rubric", the repo-sheet toggle, the stage meter's current dash). Not a colour critique: they signal "link" and "on" in ways the rest of the app does not. | `Theme.swift:89-91`; `extra-repo-detail.png`, `extra-add-repo.png` | Consistency (N4) |

### Top 10 in one line

1. Stop and post are hidden holds (tap does nothing) and are inconsistent with every other action.
2. The popover cannot say when the next sweep is, or why a run failed (copy truncated, third line dropped).
3. Five overlapping counts for one run, and "draft" appears in them with two meanings.
4. Onboarding ends in a dry run; the first real review needs more steps and a hold.
5. Posting mode, authors and flagged paths each have two or three names.
6. Sweep, run, review and "Review…" menu hide what the primary button does.
7. Repos page labels last-run PR dots as "Draft PRs"; the one control is "Default (off) / On / Off".
8. Removing a repo takes 5 steps and there is no visible way in.
9. Settings is a 30-row scroll that mixes tools, files, updates, reset and uninstall with review rules.
10. Three different post flows, two safety models, and a held review can be posted unread.

---

## 5. What was not captured

- **The live app was not launched.** It would read the real config and state and the running Sager tending job. Everything is from the fixture snapshotter, so counts and copy that depend on real data (token totals, PR titles, the "would post as comment" line on the first sweep) are fixtures.
- **AppKit-backed controls**: the popover ellipsis menu, Now's Review… menu, all NSAlert confirms, and text fields. ImageRenderer draws menus and fields as a placeholder or a prohibition sign; `extra-review-now-pr.png` and `extra-add-repo.png` show the sheet frames with blocked fields and "Loading your repos from GitHub…". Audited from code instead (`Popover.swift:637-690`, `Confirms.swift`).
- **Light mode** was rendered by the snapshotter but the app forces dark; only dark PNGs are kept.
- **Interactive states**: hover, focus, press, hold-fill, tracer and glider motion, reduced-motion behaviour, popover expand animation.
- **The "Review now / An author" tab** of the review sheet (needs a live PR list), **Settings config.toml drawer**, **Onboarding with a missing tool**, **a real paused/failed run in the window** (fixtures use the popover only).
- **Menu bar menus** (Glidepath, File, Edit, View, Sweep, Review, Window, Help): read from `Shortcuts.swift`, not rendered.
- The repo sheet was rendered at 720 × 1500 to show every row; the real sheet is 720 × 640 and scrolls, so the fold position of "Remove repo…" is inferred.
