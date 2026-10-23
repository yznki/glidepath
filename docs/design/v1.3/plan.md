# Glidepath 1.3 — "Gotham glass" redesign

The approved prototype is `docs/design/v1.3/prototype.html` (open it in a browser). It is the visual and
interaction spec. When this plan and the prototype disagree on a look or a motion, the prototype wins; when
they disagree on behaviour or data, this plan wins.

Branch: `redesign-1.3`. Each phase ends with `swift build` and
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passing, then one commit.
No attribution lines in commits.

**Build constraint:** the Homebrew formula builds with Command Line Tools, which cannot run SwiftUI macros. No
`@State`, `@Observable` or `#Preview`. Use `ObservableObject` models held with `@StateObject` (see `PopoverModel`).
Plain `swift build` (no `DEVELOPER_DIR`) must pass.

## Decisions (settled with the user)

- Dark only. The app forces dark appearance (`NSApp.appearance = NSAppearance(named: .darkAqua)`); light mode is ignored.
- Look: black glass, silver light, one signal colour for "changes requested" (default sodium amber `#D29B45`).
  Approved = near-white `#F1F1F3`, skipped = hollow grey `#4D4E56`. No other colour anywhere.
- Popover: Wallet-style stack of glass cards. Strip = avatar, name, one small-caps verdict word. Click springs a
  card open (title, `#n · repo`, reason, action). Held reviews: light breathes; "Hold to post" fills like liquid;
  swipe a held card away to discard. A running card has a silver tracer around its edge and shows its stage word.
- Avatars: real GitHub photos, rendered grayscale, initials on graphite as fallback.
- Window sections: Now (default), Reviews, Repos, Schedule, Settings. Overview is replaced by Now.
- Stop a sweep = hold to stop (replaces the confirm dialog). Post = hold to post (replaces the confirm dialog).
- Review draft PRs: global setting + per-repo override (inherit / on / off). Draft PRs get normal verdicts.
- Every setting in the prototype is real, including glass blur.
- Settings that only change the app's look live in `UserDefaults` (`@AppStorage`): glyph style, badge, signal
  colour, glass blur, motion. Everything that changes reviewing lives in `config.toml`.
- Settings-page review options (posting, strictness, model, authors, own PRs, bots, flag paths, gitnexus) write the
  global value; per-repo values in Repos override them where they already exist per repo.

## Phase 1 — Config and runner (backend)

All parse/render/edit code follows the existing `notify` pattern end to end (Config.swift parse + allowlist +
render, ConfigEdit.swift setter, tests in ConfigTests/ConfigEditTests).

New top-level keys (all optional, defaults in brackets):

| key | type | default | used by |
|---|---|---|---|
| `review_drafts` | bool | false | Filter |
| `include_bots` | bool | false | Filter |
| `model` | "haiku" \| "sonnet" \| "opus" | "opus" | Claude.arguments |
| `strictness` | "relaxed" \| "easygoing" \| "balanced" \| "exacting" \| "ruthless" | "balanced" | review prompt |
| `notify_changes_only` | bool | false | Notifier |
| `notify_sound` | "none" \| "glass" \| "pop" \| "tink" \| "hero" | "glass" | Notifier |
| `respect_focus` | bool | true | Notifier |
| `monthly_tokens` | int, 0 = no budget | 0 | runner preflight, Settings meter |
| `pause_at_budget` | bool | true | runner preflight |
| `dry_run` | bool | false | runner (post nothing, same as the existing dry-run path) |
| `hotkey` | bool **or** string like "⌥⌘G" | true | GlobalHotkey (bool keeps today's meaning) |

Per repo (`[[repo]]`): `review_drafts` = bool, optional; absent = inherit the global value.

Runner and filter changes:
1. `PRFilter.evaluate` gains `reviewDrafts: Bool` and `includeBots: Bool`. Draft skip only when `!reviewDrafts`;
   bot skip only when `!includeBots`. Caller (`CLI/Run.swift` ~343) passes repo override ?? global.
2. `Claude.arguments` takes `model: String` instead of hard-coded "opus".
3. Strictness: append one sentence to the review prompt per level (table in `Core/Review.swift` or next to the
   prompt builder): relaxed "Let style and small things go; flag only real bugs.", easygoing "Flag only what could
   break.", balanced "" (today's prompt), exacting "Also flag naming, missing tests and unhandled edge cases.",
   ruthless "Flag every issue you find, including nits."
4. Budget: before a scheduled sweep, sum `RunState.tokens` of runs started this calendar month
   (`RunStore.loadAll`). If `monthly_tokens > 0 && pause_at_budget && used >= monthly_tokens`, finish the run at
   once with error "Monthly token budget reached". Manual "Run now" ignores the budget.
5. Timed pause: `Pause.set` gains an optional `until: Date?` written into the pause file; `isPaused` returns false
   (and removes the file) once `until` has passed. Popover/Schedule offer: Running / Pause 1 h / Until tomorrow
   (tomorrow = next scheduled sweep day at its first time).
6. Live tokens: store `sessionId` in `RunState` when the runner starts claude. The app polls
   `Transcript.usage(paths:cwd:sessionId:keptPRs:)` every 2 s while a run is live and shows the totals on Now.
7. Notifier: sound by name (`UNNotificationSound(named: UNNotificationSoundName("Glass"))` etc., none = no sound);
   skip the notice when `notify_changes_only` and the sweep has no changes verdict; `respect_focus == false` sets
   `interruptionLevel = .timeSensitive` (may be downgraded by macOS without the entitlement; acceptable).
8. Hotkey string: parse "⌃⌥⇧⌘" + key into carbon modifiers and a `kVK_*` code; `GlobalHotkey` registers it.
   `true` = ⌥⌘G, `false` = off.
9. Schedule stays a list of times in config. Add `ScheduleWindow` (pure): `times(start:end:every:) -> [ScheduleTime]`
   and `infer(from: [ScheduleTime]) -> (start, end, every)?` (nil when the times are not evenly spaced).
   Tests for both, including a window that crosses midnight.

Tests: every new key parses, rejects bad values, renders and round-trips; filter tests for drafts/bots with and
without the flags and the per-repo override; ScheduleWindow tests; budget sum test; timed pause test.

## Phase 2 — Foundations (UI kit), new folder `Sources/Glidepath/UI/`

- `Gotham.swift`: colour tokens from the prototype `:root` (void, mat, edge, fg, mute, tint, hi, row, approve,
  changes, skipped), `signal` read from `@AppStorage("signalColour")` (amber/crimson/ice/mono → hex from the
  prototype `ACCENT`), type helpers: `.cap()` (9.5 pt semibold, tracking 0.2 em, uppercase, mute),
  thin numerals (`.system(size:weight:.ultraLight)` + `monospacedDigit()`).
- `Glass.swift`: `GlassCard` view modifier — `.ultraThinMaterial` (blur strength scaled by `@AppStorage("glassBlur")`,
  0 = solid tint) + tint fill + top hairline highlight gradient + inner shadow + drop shadow + optional verdict
  light (blurred circle top-right, opacity per verdict, breathing when held) + specular highlight following the
  cursor (`onContinuousHover`).
- `Tracer.swift`: rotating `AngularGradient` stroke (transparent → white at the end), used on running cards, the
  run button and the Now page rows. Respects reduced motion (static ring).
- `HoldButton.swift`: press-and-hold control. Fill grows over 0.9 s while pressed, drains at 3× speed on release,
  fires `action` at 100 %. Keyboard: Space/Return held. Label text and colour parameters.
- `Avatar.swift`: loads `https://github.com/<login>.png?size=96` with `URLSession`, caches to
  `~/Library/Caches/Glidepath/avatars/<login>.png` for 7 days, draws grayscale; graphite gradient + initials
  fallback (gradient lightness from the login hash, as in the prototype `avBg`).
- `Motion.swift`: spring presets (`.spring(response: 0.42, dampingFraction: 0.86)` for stack moves, `0.35/1.0`
  default, `0.4/0.8` for tilt and swipe release) and a `@AppStorage("motion")` reduced flag that also honours
  `accessibilityReduceMotion`.
- App forces dark appearance at launch.

## Phase 3 — Menu bar and popover

- `MenuBarLabel`: glyph style from `@AppStorage("glyphStyle")`: glider (current drawing), dot, count. Badge dot when
  reviews wait (`@AppStorage("glyphBadge")`). While running, the glider tilts/bobs (existing `SweepTicker`).
- `Popover.swift` rewritten as the stack (prototype `layout()`): header = three thin numerals with cap labels
  (Approved / Changes / Skipped, click filters) + round run button (tracer while running; hold-to-stop when running).
  Cards: strip height 64, overlap step `min(56, (420-64)/(n-1))`, open card 232. Hover lifts card 3 pt, cards below
  shift 8 pt. Tilt ±4°/±5° from the cursor. Click toggles open; open card moves to top, the rest pile below.
  Horizontal drag on a held card: 1:1, release projects with `v*0.998/(1-0.998)/1000`; past 160 pt discards
  (`store.discardDraft`), otherwise springs back. Non-held cards rubber-band. Hold to post → `store.postDraft`.
- Keep every existing shortcut (↑↓ moves, Return opens/closes the card, ⌘R, ⌘., ⌘O, ⌘,, Esc).
- Remove the `NSAlert` confirms for post (hold replaces them). Keep the size-skipped "Review" action inside the open card.

## Phase 4 — Window

- Sidebar: Now, Reviews, Repos, Schedule, Settings (prototype look).
- Now (`Window/Now.swift`, replaces Overview): big clock (elapsed while running, countdown to `snap.nextRun`
  otherwise), stats (tokens, queued, waiting, last sweep duration), Run now / hold to stop, repo rail (listing /
  indexing / reviewing / done from `run.phase` and repo order), pipeline rows with Gather · Review · Check · Land
  nodes from `Strip.stage`, per-PR tokens. Clicking a finished row opens it in Reviews.
- Reviews: grid of open glass cards (prototype `renderGrid`), tally filter in the header, hold to post / discard.
  Keep the existing detail view for full review text as a sheet from the card.
- Repos: grouped list in the prototype style; add the drafts segmented control (Default / On / Off) per repo.
  Keep the existing detail and Add Repo sheet, restyled.

## Phase 5 — Schedule

`Window/Schedule.swift` rewritten as the dial (prototype `dialSVG`, `buildSchedule`): 24 h ring, midnight on top,
draggable start/end knobs (15 min snap), centre drag/scroll/±/arrow keys for the interval (15–240 min, step 15),
sweep dots, next-sweep dot breathing, now hand in the signal colour, hour labels. Presets animate the dial. Day
pills. Stats (sweeps a day / week / tokens a month vs budget). Upcoming strip of the next 8 sweeps. Pause segmented
control. Saving writes `ScheduleWindow.times(...)` through `ScheduleEditor.setSchedule` + `setDays` (debounced
0.4 s after the last drag) and reinstalls the launchd job as today. When the saved times are not evenly spaced the
dial shows them as dots with no arc until the user drags.

## Phase 6 — Settings

`Window/Settings.swift` rewritten as the prototype: search field (filters rows and hides empty groups), sticky
section chips, groups Reviewing / Notifications / Menu bar / Look / Budget / Advanced with every row in the
prototype, sound preview (`NSSound(named:)`), shortcut recorder (local key monitor, Esc cancels), budget ring from
this month's runs, "Show config.toml" drawer that renders the real file and highlights lines that changed, toast.
Keep the existing updates row, tools row, uninstall section (moved under Advanced).

## Phase 7 — Finish

Update `--snapshot` fixtures, `docs/design.md`, README screenshots, version 1.3.0, formula after release.
