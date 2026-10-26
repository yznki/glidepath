# Glidepath 2.0 experience: spec

Status: draft for Yazan's approval, 2026-10-26.
Inputs: `audit.md` (1.5), `audit-1.10.md` (1.10), `research.md` (rulebook). Rule numbers like R12 point to the
rulebook in `research.md`. Problem ids like P3 and N4 point to the two audits.

The look stays: dark Gotham black glass, silver light, one amber signal colour. This spec changes structure, words and
interaction, not the material.

## 1. The problem in one paragraph

1.10 has 61 user-facing concepts, 6 sidebar pages, 46 settings rows, 4 places that show "needs you" with 4
different counts, 3 ways to post, 7 hold buttons, and two vocabularies on top of each other (sweep/run/round and
approach/plane/tower/runway/gate/marker). Every screen answers several questions at once and none answers the first
question, "is it fine, and does it need me?", in words. You cannot stop tending from the app.

## 2. The idea

Glidepath looks after pull requests. There are only two kinds:

- **Team PRs**: Glidepath reviews them for you.
- **Your PRs**: Glidepath keeps them moving: fixes CI, answers comments, merges when ready.

Everything in the app is about one of those PRs, so the app is organised around PRs, not around runs, rounds or
metaphors. Every surface opens with one sentence that says what is going on and whether you are needed.

## 3. Vocabulary (61 concepts to 14)

| Word | Means | Replaces |
|---|---|---|
| **Check** | One pass over your repos. "Next check 5:00 PM", "Check now" | sweep, run, round, tend round, next look, session |
| **Review** | What Glidepath writes on a team PR | review draft, held review, landed (as a verb for posting) |
| **Needs you** | Something only you can decide. One list, one count, everywhere | waiting for you, holding, stuck, blocked, your call, held |
| **Ready to post** | A review written and waiting for you | held, draft, Hold for me, not posted |
| **Fix ready** | A CI fix for your PR waiting for you to push | held fix, Hold to push |
| **Reply ready** | A drafted answer to a reviewer | your call, draft reply |
| **Ready to merge** | Your PR has passed everything | cleared, Ready to land, Inner · Ready |
| **Stuck** | Glidepath tried and gave up; says why | holding, stuck, blocked, main broke |
| **Skipped** | Not reviewed, always with the reason | skipped, too large, draft PR |
| **Ask first** / **Autopilot** | Glidepath asks before anything goes to GitHub, or it doesn't | posting modes, Approved fixes, Landing, When Glidepath disagrees |
| **Pause** | Stops everything until a time you pick | Pause, Pause 1 h, Until tomorrow, hands-off, Tend my PRs off |
| **Quiet hours** | When heavy work (split plans, tidying what was learned) is allowed to run; outside them it waits | unchanged, but edited as two times and days |
| **Learned** | Rules and commands Glidepath picked up for a repo | playbook, lesson, verified command, teach |
| **Activity** | What happened, newest first | History, Tower, Rounds today, Briefing |

Cut from the UI entirely (kept in code and config if needed): approach, plane, marker, gate, runway, tower, lane,
in the air, flight recorder, round, try, council (shown as "Asked a second opinion"), sweep, landed, briefing,
playbook, tend, hands-off. A GitHub "draft PR" is always written "draft PR", never "draft".

## 4. Structure

### 4.1 Menu bar icon (R2, R3)

Four states, each with its own shape, so colour is never the only signal:

| State | Shape | Meaning |
|---|---|---|
| Quiet | the glyph | Nothing needs you, nothing running |
| Working | the glyph with a slow moving tracer | A check is running |
| Needs you | the glyph + a number | Count = the Needs you list, the same number everywhere |
| Problem | the glyph with a slash or pause bars | Paused, or something is broken and needs a fix |

Left click: popover. Right click: a native menu with Check now, Pause ▸, Open Glidepath, Settings…, Quit.

### 4.2 Popover: "is it fine, and does it need me?" (360 pt, never taller than 520 pt)

1. **Status sentence** with one control on the right:
   - "All good. Next check at 5:00 PM." [Check now]
   - "Checking 3 PRs in lumen/web…" [Stop]
   - "2 things need you." [Open]
   - "Paused until 9:00 AM." [Resume]
   - "Can't reach GitHub: sign-in expired." [Fix]
2. **Needs you**: up to 4 rows. Each row is one PR: title, repo #n, what it needs ("Review ready to post",
   "Fix ready to push"). Click the row and the window opens on that PR. No actions in the popover rows. The popover
   only tells you; you decide in the window, where you can read what you're approving (fixes P10, N5).
   If there are more than 4: "and 3 more".
3. **Since you last looked** (only when there is something): one line, e.g. "Posted 3 reviews, merged #1246".
4. Footer: Autopilot state as words ("Ask first" or "Autopilot on"), Pause ▸ menu, window button.

Gone from the popover: the three numerals, the stats line, the digest, the mini chart, the tend block, the ellipsis menu
(its items move to the right-click menu and the app menu).

### 4.3 Window: four pages (R44)

Sidebar: **Inbox**, **PRs**, **Activity**, **Repos**. Settings is its own window (⌘,). The sidebar carries no status
footer; status lives in the page header.

Every page starts with the same header: page title, then the status sentence from the popover, then at most one
primary button on the right.

#### Inbox (⌘1): what needs you

- Header: "2 things need you" / "Nothing needs you. Next check at 5:00 PM."
- **Needs you** list, oldest first. One row per PR. Row: avatar, PR title, repo #n, what it needs in amber, one-line
  reason. One primary button on the right that names the action: **Post review**, **Push fix**, **Send reply**,
  **Merge**, **Open revert PR**. A "…" menu holds the rest (Open on GitHub, Discard, Try again, Edit, Review anyway).
- Clicking the row (not the button) opens the PR page.
- **Working now** (only while a check runs): one line per PR being worked on, with a plain stage: "Reading the diff",
  "Checking findings", "Fixing CI".
- **Done today** (collapsed): what was posted, merged, skipped, with reasons (R17).
- Empty state: "Nothing needs you." and the next check time. Nothing else.

#### PRs (⌘2): where every PR stands

Two tabs at the top: **Team PRs** and **Your PRs**. Each is a plain list grouped by state.

- Team PRs groups: Ready to post · Reviewed · Skipped (with reason) · Not checked yet.
- Your PRs groups: Needs you · Glidepath is on it · Waiting on reviewers · Ready to merge · Merged this week.
- Every row has the same four-step progress strip for your PRs: **CI · Comments · Approval · Merge**, each a filled,
  hollow or amber dot with the word underneath on hover. This replaces the Approach chart, markers and gates (N8).
- Click a row: the **PR page** slides in over the list (one level, Back returns):
  - Title, repo, author, and the status sentence for this PR ("Waiting for Gadi's approval since yesterday").
  - Primary action if any (same names as Inbox).
  - For team PRs: the review as it will appear on GitHub, findings with severity (Must fix / Should fix / Nit), and
    what Glidepath checked. "Show how it got there" opens the full log (the old flight recorder).
  - For your PRs: the progress strip, then a timeline of what Glidepath did on this PR ("Fixed a failing test, pushed
    a3f9c1", "Replied to Gadi and resolved the thread"). Footer switch: "Look after this PR" (replaces hands-off).
  - Split proposals open here, not in a separate builder entry point.

#### Activity (⌘3): what happened

One feed, newest first, grouped by day: checks, reviews posted, fixes pushed, replies sent, merges, things learned.
Each entry is one sentence that names the PR and repo and links to its PR page. Filter chips: All · Reviews · Your PRs ·
Problems. Problems carry a Fix or Show log button. The morning summary becomes the first entry of the day
("Overnight: merged 2, 1 stuck"), not a card you must dismiss.

#### Repos (⌘4): what Glidepath watches

List of repos, each row: name, two switches **Review team PRs** and **Look after my PRs**, and the last check result.
Row click opens the repo page (same slide-in as PRs):
- Who to review (Everyone / Collaborators / These people), using the same words as onboarding and Settings.
- Review rules (file and Extend/Replace).
- Learned: rules and commands, each with Remove. A field "Teach Glidepath a rule".
- Look closer at (flagged paths).
- **Remove repo** at the bottom, with Undo, not a confirm dialog. Also in the row's right-click menu.

### 4.4 Settings window (⌘,), four panes, about 18 rows (R37–R43)

| Pane | Rows |
|---|---|
| **General** | Open at login · Show in menu bar · Notifications (Needs you only / Everything / Off) · Claude account |
| **Schedule** | Plain sentence ("Weekdays at 9:00, 1:00 and 5:00") · Presets (Workday, Every 2 hours, Once a day, Custom) · Custom = the 24 h dial plus a list of time chips that do the same thing · Days · Quiet hours (two time pickers + weekend switch) · Keep for myself: usage reserve slider with the current usage shown |
| **Behaviour** | **Ask first / Autopilot** as one big two-option control, with a sentence underneath that lists exactly what Autopilot does on its own. Switching to Autopilot needs a hold and states the consequence (R43). Under Ask first only: What to post (Comment / Full review). Review strictness. Size limit. |
| **Advanced** | Config file · Logs · Model and budget · Linear key · Reset · Uninstall |

The look settings (glass blur, icon, signal colour) move under General > Appearance, collapsed. The settings search
goes; four panes don't need it.

### 4.5 Onboarding: three steps (R50)

1. **Tools**: checks claude, gh, git on its own. Only shows up if something is missing, with a Fix button.
2. **Repos**: pick repos. Two switches under the list: "Review my team's PRs" (on), "Look after my own PRs" (off).
3. **Done**: "Glidepath will check at 9:00, 1:00 and 5:00 and ask before posting anything." [Check now] [Later]

Check now is a real check in Ask first mode: nothing reaches GitHub without you, and the first results land in Inbox.
No dry run (P4). Schedule, rules and Autopilot are offered later as one-line tips in the Inbox empty state.

## 5. Interaction rules

1. **One button per row, named for its result.** Never "Review…", "Open", "Hold to post" as a label.
2. **Anything that goes to GitHub as you is a hold, and only that.** The button reads "Post review", shows a ring that
   fills while held, and a tap shows "Hold to post" under it with a small shake. Same component, same 0.6 s, for
   Post review, Push fix, Send reply, Merge, Open revert PR, and turning on Autopilot. Nothing else is a hold (P1, P10).
3. **Discard and Remove are instant with Undo** for 8 seconds, plus ⌘Z. No confirm dialogs (R13).
4. **Stop is a click.** It stops whatever is running, review or your-PR work (N2). Pause has durations and always shows
   when it ends.
5. **One Needs you count** computed in one place and shown in the icon, popover, Inbox header and sidebar badge (N4).
6. **Every problem names the fix and has a button for it** and stays until fixed (R30, R32).
7. **Skipped always says why** (R17).
8. **Keyboard**: J/K move, Return opens, hold Space for the primary hold action, ⌘Z undo, ⌘. stop, ⌘R check now.
   The shortcuts sheet shows these 8, not 55.

## 6a. Native first (decided 2026-10-26, overrides 6 where they clash)

Yazan: the current app and the HTML prototype both look and feel bad: cheap, crowded, unclear, clunky. North star:
Apple's own apps on macOS 26 (System Settings, Music, Notes). So the hand-built Gotham kit goes. Glidepath uses the
system's own components and lets them carry the glass:

- `NavigationSplitView` with a real source-list sidebar, `List`/`Table` for rows, `Form(.grouped)` for every setting,
  a `Settings` scene with a toolbar of panes, `.toolbar` items, `.searchable`, `.inspector` for the PR page, native
  `Menu`, `Toggle`, `Picker`, `ProgressView`, `ContentUnavailableView` for empty states, `MenuBarExtra(.window)`.
- macOS 26 Liquid Glass comes for free on the sidebar, toolbar, popover and sheets. Custom glass only through
  `glassEffect` on the few custom pieces (status header, hold button). No hand-drawn blur, no custom sidebar.
- SF Symbols only, system text styles only (`.largeTitle`, `.title3`, `.headline`, `.body`, `.callout`,
  `.subheadline`, `.footnote`), system spacing. Dark appearance kept, app tint = amber, used only for "needs you".
- macOS 14–15 get the same layout with standard materials. No second design. (Confirmed by Yazan: keep macOS 14+.)
- Trust ramp (approved): new installs review team PRs only, in Ask first. After a few good checks the Inbox offers
  "Look after my PRs", later "Autopilot", one step at a time, each a one-line offer that can be dismissed.

Section 6 below stays as the intent; where it names sizes, the system text styles win.

## 6. Visual rules inside the existing look

- Three text sizes: 22 semibold (page title), 13 regular/semibold (everything), 11 medium (secondary). 15 semibold
  for the status sentence only. No 9.5 pt caps labels; section labels are 11 pt sentence case.
- Amber means "needs you" and nothing else. Verdict words are silver; "Must fix" gets a filled silver dot.
- Glass on the sidebar, toolbar, popover and sheets. Content rows sit on the quiet black, separated by space, not
  boxes. No cards inside cards.
- One row height for lists (52 pt), one corner radius family.
- System blue and green go (P22): links are silver underlined on hover, switches use the silver tint.

## 7. What this cuts

| | 1.10 | 2.0 |
|---|---|---|
| Concepts | 61 | 14 |
| Sidebar pages | 6 | 4 |
| Settings rows | 46 | about 18 |
| Places showing Needs you | 4, 4 counts | 4, 1 count |
| Ways to post a review | 3 | 1 |
| Hold buttons | 7 kinds | 1 component, outward actions only |
| Onboarding steps | 6 | 3 (2 if tools are fine) |
| Text sizes | 20 | 4 |

## 8. Open questions for Yazan

1. Drop the aviation words and the Approach chart for plain words and a progress strip? (Recommended: yes.)
2. Popover rows only open the window, no posting from the popover? (Recommended: yes; you read before you post.)
3. Schedule moves into Settings rather than its own page? (Recommended: yes; you set it once.)

## 9. Concept: the glide line (approved direction 2026-10-26)

Yazan approved the native prototype ("feels good"), asked for more creativity and more glass, graphite accent for
switches and sidebar, PR details in the right-hand panel. The awwwards method is for websites; we borrow its concept
discipline, not its stack.

Concepts considered:
1. **The glide line** (picked). A single line of light, the path a glider takes down to land, is the one living object
   in the app. It is the status. Anchor: the product's own name. Not portable to another app.
2. Refraction panes: rows as thick glass that bends the content behind it. Pretty, no meaning. Rejected.
3. Instrument dial: the schedule dial as the home screen. Too much like the old Gotham kit. Rejected.

Concept card:
```
Idea:        Glidepath is calm when everything has landed. One line of light shows how far things are from done.
Metaphor:    a glider's final approach: long, smooth, unhurried descent to a soft touchdown. Visual only, never words.
Signature:   holding Post review fills the row's glass with light along the line; on release the row glides down
             and to the right, shrinks, and settles into the "Done today" count, which ticks up. The line dims one bead.
Emotion:     calm control. First second says "fine" or "2 things, here they are".
Motion verb: glide and settle. Long ease-out, no bounce, things travel a shallow diagonal, never pop straight up.
Screenshot:  the window over a wallpaper, fully translucent, the glide line across the top with two amber beads,
             two glass rows beneath it.
```

Where the line lives (one component, `GlideLine`, driven by one value: the store's state):
- **Window header**: a thin luminous line under the title, full width, on a glass band. Needs-you items are amber
  beads sitting on it. While a check runs, a soft tracer of light travels along it, left to right, once per PR.
  All clear: the line lies flat and quiet with one slow breath of brightness every few seconds (idle state).
  Problem: the line breaks with a gap where the problem is; the gap is the Fix button.
  Paused: the line goes dotted.
- **Popover**: the same line, smaller, across the top, same beads.
- **Menu bar icon**: the glyph is the line itself as a template image: flat (quiet), with a moving dot (checking),
  with a count (needs you), broken (problem/paused).
- **Empty Inbox**: the touchdown moment. When the last item is handled the line settles flat, brightens once, and
  "Nothing needs you" fades in under it with the next check time.

Glass, more of it (macOS 26 Liquid Glass, native APIs only):
- Window background is translucent glass over the desktop (`.containerBackground` with glass / a clear window
  background) so the wallpaper reads through, like Control Center.
- Needs-you rows are separate glass panes inside a `GlassEffectContainer`, with `.interactive()` glass that responds
  to pointer and press. Done/history lists stay plain text on the window glass (glass for things you act on only).
- Selecting a row morphs its glass into the inspector panel (`glassEffectID` + namespace); closing morphs back.
- Hold button: the light fills the glass pane itself, not a ring.
- Popover is one glass sheet with the line on top.
- Graphite accent everywhere; amber only for beads and "needs you" text.
- Reduce Motion: no tracer, no glide, no breath; state changes cross-fade. Reduce Transparency: system solid fallback.

## 10. Decisions from phase 1 (2026-10-26)

- Quiet hours: heavy work runs only inside them (1.10 behaviour); §3 corrected.
- "Try again" is the one allowed use of "try".
- Main broke shows as **Revert ready** with Open revert PR.
- The count counts items, not PRs; one PR can need two things.
- New need kind **Needs your answer** (a reviewer question with no drafted reply). Too-large PRs read "Skipped: too large".
- Status priority: problem, paused, checking, needs you, holding back, quiet.
- Pause stops running work; Stop does not pause.
- Engine reasons still use old words ("5 rounds a day reached"); reword at the source in phase 7.
