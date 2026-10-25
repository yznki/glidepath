# 1.5.0: Now as an inbox

Approved prototype: `docs/design/now-inbox/prototype.html` (states: after a review, reviewing, all clear).

The current Now is a scheduler dashboard: a giant clock, stats, a repo rail, and one pipeline row per PR, including
rows carried over from earlier runs and dozens of skipped ones. The answers to "what needs me" and "what just
happened" get lost. 1.5.0 reorganises Now, Reviews and the popover around those two questions.

## Rules

- Must build with Command Line Tools: no `@State`, `@Observable`, `#Preview`. Views keep state in
  `ObservableObject` models, as the existing code does.
- Never change `Config.parse` defaults.
- Match the surrounding comment style: one `///` line per type or func, saying what it is for.
- Reuse what exists: `Gotham` colours, `Avatar`, `HoldButton`, `SettingButton`-style buttons, `ReviewNowSheet`,
  `ReviewSheet` (the flight recorder), `Store.postDraft`, `discardDraft`, `reviewPR`, `runNow`, `stopRun`,
  `allRuns`, and `liveTokens`.

## Phase 1: Core (`RunDigest`)

1. `RunState.target: String?`. It is optional, so older run files still decode.
   - The runner sets it where it creates a by-hand run (`Run.swift`, around `RunState.new(... kind: "review")`).
   - Author target: `"author:<login>"`.
   - PR target: `"prs:"` followed by `owner/name#n` entries joined with `,`.
2. New `Sources/Glidepath/Core/RunDigest.swift`, a pure struct built from `(run: RunState, running: Bool)`.
   - **Own rows** are the rows with `carriedFrom == nil`, each paired with its repo slug. Carried rows belong to
     the run they came from and never appear in this digest.
   - **title**:
     - A sweep (`kind == nil`) is titled "Sweep".
     - An author target is titled "<login>'s PRs".
     - A target with one PR is titled "owner/name #n".
     - A target with several PRs is titled "<k> PRs".
     - A review with no target is titled "Review".
   - **Buckets**:
     - `inFlight`: `active`.
     - `reviewed`: verdict `approve` or `changes`, including held drafts.
     - `stopped`: not active, no verdict, and the run is not running.
     - `skipped`: verdict `skipped`, grouped by `SkipKind` in this order:
       - `own`: reason "your own PR".
       - `bot`: reason "bot author".
       - `alreadyReviewed`: reason starts with "already reviewed".
       - `draft`: reason "draft".
       - `tooLarge`: skipReason "size" or reason starts with "too large".
       - `other`.
   - **lead** (bold part):
     - While running: "<done> of <toReview> reviewed". `toReview` counts the own rows that are not skipped; `done`
       counts the rows among those with a verdict.
     - When finished with stopped rows: "Reviewed <r>, <s> stopped."
     - When finished with r == 0 and nothing stopped: "Nothing reviewed."
     - Otherwise: "Reviewed <r> of <own count>."
   - **rest**:
     - When the skips are all `alreadyReviewed`: "You'd already reviewed the other <k>, and nothing changed since."
     - When there are other skips: "<k> skipped: " followed by the groups in order, joined with ", ". The groups
       read "11 yours", "1 bot"/"7 bots", "2 already reviewed", "1 draft"/"2 drafts", "1 too large" and "3 other".
     - When nothing was skipped: an empty string.
3. Tests in `Tests/GlidepathTests/RunDigestTests.swift`:
   - Title for each target form.
   - Carried rows are excluded.
   - The Eleyy case: 4 reviewed and 21 already reviewed give "Reviewed 4 of 25." plus the already-reviewed
     sentence.
   - A mixed sweep gives "Reviewed 5, 2 stopped." with grouped skips.
   - The running lead.

## Phase 2: Window

### Now (`Window/Now.swift`, rewrite the body)

- **Header**:
  - Left: "Now".
  - Right: a status line, then a primary **Review…** button. The button is a `Menu` with three items:
    - "Sweep all repos now" calls `store.runNow()`. It is disabled while a run is going.
    - "Review PRs…" opens `ReviewNowSheet` on the PR mode.
    - "Review someone's PRs…" opens it on the author mode.
  - Status line:
    - Idle: "Next sweep 8:00 PM · in 3 h 41 min".
    - Paused: "Paused".
    - Running: "Reviewing <digest title> · m:ss", counting elapsed time.
  - Remove the clock, the stat row, the repo rail and the pipeline header.
- **Needs you** (shown when there are any): the current run's strips with `draft == true` and verdict `approve`
  or `changes`.
  - Each row has an avatar, the title, then "<Verdict> · <reason> · <repo> #n" with the verdict coloured.
  - Trailing: a ghost "Discard" and the existing `HoldButton` "Hold to post". Posting stays a hold, because it
    publishes.
  - Use a faint amber row background, as in the prototype.
  - The section header reads "NEEDS YOU" with the amber count.
- **All clear** (shown when there are no held drafts and nothing is running): the centred message "Nothing needs
  you" with "Every open PR is reviewed at its latest commit." under it.
- **Recent**: `RunCard` for the 3 newest runs from `store.allRuns()` (the current run included, newest first).
- Tapping any PR row opens the flight recorder sheet, as Now rows do today.

### `RunCard` (new `Window/RunCard.swift`, shared by Now and History)

- **Header**: the digest title, then the meta on the right.
  - Finished: "4:30 PM · 14 min · 1.7M tokens".
  - Running: "started 4:30 PM · 188k tokens" from `liveTokens`, plus a ghost "Stop" that calls the existing stop
    confirmation or `store.stopRun()`.
- **Sentence**: the digest lead in the foreground colour, then the rest in muted text.
- **While running**: a 2 pt progress bar showing done / toReview.
- **Rows, in order**:
  - In-flight rows: a small 4-dot track (done / active pulsing / pending) and the stage word.
  - Reviewed rows: the coloured verdict word, the reason, and "#n". Trailing text is "posted", "held" or
    "not posted". Show at most 5, then a fold "N more reviewed".
  - Stopped rows: muted "Stopped in <stage>", then "no result", then "#n". Trailing: "Review again", which calls
    `store.reviewPR`.
  - A fold "<k> already reviewed by you" that expands to chips "#n".
  - A fold "<k> skipped" that expands to chips "11 your own", "7 bots", "1 draft · #1313" and so on.
- Folds are collapsed by default. Keep their state in an `ObservableObject`.

### History (the Reviews section, renamed)

- The section title, sidebar label, window title, shortcut title and popover button all become "History". Keep the
  enum case name if renaming it is noisy.
- The body is every run as a `RunCard`, newest first, under day headings: "Today", "Yesterday", or "Mon 20 Oct".
- Delete the glass card grid. Keep `ReviewRow` and whatever else `FlightRecorder.swift` needs.
- The sidebar badge (`waitingCount`) moves from History to Now.

## Phase 3: Popover

- The card stack shows only held drafts and in-flight rows.
- Below the stack, a digest line for the newest run shows its title, its lead and rest (2 lines max), and an
  "Open" that calls `WindowRouter.shared.open(.now)`.
- The header counts (approved, changes, skipped) come from the newest run's own rows only, never carried rows.
- When nothing is held or running, the stack area shows "Nothing needs you".

## Fixtures and snapshots

- Update `WindowFixtures` and the popover fixtures so they give these states:
  - Now after a review: 2 held drafts, a finished author run with 4 reviewed and 21 already reviewed, and an
    earlier sweep with reviewed, stopped and skipped rows.
  - Now while reviewing.
  - Now all clear.
  - History.
  - Popover.
- Where a fixture is a by-hand review that follows a sweep, its rows carry `carriedFrom`, as the real runner
  writes them.
- Keep the existing snapshot names where the state still exists.

## Verify

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: all tests pass.
- `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build -c release`: builds.
- `.build/release/glidepath --snapshot /tmp/gp-v15`: renders.
- CHANGELOG `## Unreleased`:
  - Now shows what needs you and what each run did, in one sentence per run.
  - Skipped PRs fold away.
  - Reviews is now History.
  - The popover shows only what needs you.
