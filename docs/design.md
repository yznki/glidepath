# Glidepath: design

The menu bar app shows a sweep as an approach profile. Each PR flies down a glide slope to a runway and lands with
a verdict. Left to right is progress. The popover answers "do I need to act?" first.

Tagline everywhere: "PRs reviewed before you're back."

This is the final design (design pass 4 wins where earlier passes conflict; the pre-launch fixes come after it). Gaps between the brief and the build are
listed at the end, with the reason.

## 1. Header

Every header line starts at x = 16. No coloured dots before a headline.

| State | Line 1 (17/600) | Line 2 (13) | Line 3 (12, tertiary) |
|---|---|---|---|
| running | "3 in flight, 4 landed" (in flight: active PRs; landed: PRs with a verdict) | "2 need changes" in changes text (13/500); with none, no line 2 | "Started 10:12 AM" |
| idle, changes | "2 need changes" | "Last sweep 10:12 AM · 7 PRs" | "Next sweep 1:00 PM, in 38 min" |
| idle, clear | "All clear" | "Last sweep 10:12 AM · 3 PRs" | "Next sweep 1:00 PM, in 38 min" |
| paused | "Paused" (changes text) | "Last sweep 10:12 AM · scheduled sweeps skipped" | "Paused since 10:35 AM" |
| failed | "Last sweep failed" (error) | the one-line reason in plain words, e.g. "The review agent stopped early (exit 1)" | "Retrying at 1:00 PM · Open log" (Open log 13/500, error colour, no underline) |
| empty | "No open PRs" | "Watching 2 repos · last sweep 10:12 AM" | "Next sweep 1:00 PM, in 38 min" |
| first run | "Ready for the first sweep" | "Pick the repos Glidepath should review." | "First sweep at 1:00 PM" |
| not scheduled | "Not scheduled" (changes text) | "Run `glidepath init` to set it up" | none |

Times use the user's locale (`Date.FormatStyle` `.hour().minute()`), never a hard-coded 24-hour format.
Tokens are not in the header. They are in the ellipsis menu as a disabled item.

## 2. Approach profile

The profile is in every state, at full width (328 pt). Two heights:

- **Running** (64 pt): the sweep in progress. Stage labels, numbered dots, landed marks.
- **Quiet** (36 pt): every other state. No stage labels and no dots.

Shared rules:

- **Runway**: 2 pt bar from x = 268 to 328, #D0D0D0 (light) / #4A4A4A (dark), in every state. Landed marks sit on it.
- **Slope**: 2 pt line, #3A3A3C (light) / #D0D0D0 (dark).
- **Landed marks** (10 pt), on the runway in list order, 16 pt apart (a 6 pt gap), the first starting at the runway's
  left end (x = 268). Past four marks the spacing tightens to fit the 60 pt runway, and past six the marks shrink.
  - approved: filled circle, #1F8A52 (light) / #3DD68C (dark);
  - changes: filled triangle, #B86E00 / #FFB020;
  - skipped: dash, #6B6B6B / #9A9A9A;
  - no result (finished without a verdict): hollow grey circle.
  - carried over from an earlier sweep: drawn in tertiary grey (the shape is unchanged).
- **Motion** (running only): each in-flight circle slides along the slope by at most 6 pt and back, on a 4 s ease-in-out
  loop. On landing, the circle slides onto the runway in 0.7 s with an ease-out curve and becomes its mark. Reduced
  motion: final positions only.
- **Hover**: one 2 pt ring in the mark's colour, 5 pt outside the mark. No second ring.

Running (64 pt):

- **Slope**: from (0, 36) to (268, 52), so the stage labels sit above it, clear of the tick row.
- **Stage labels**: "gather", "review", "check", "land", each centred over its stage x (see Stage columns), in the top
  row (y = 0 to 12). 11/500 tertiary. The "land" label is centred over the runway (x = 298), above the landed marks.
- **Stage columns**: stage n is centred at x = (n - 0.5) / 4 * 268.
- **In-flight PRs**: a 10 pt circle in the system blue, spread 11 pt apart along the slope within their stage. Each is
  labelled with its number ("#1113", 11/500 tertiary). Every number sits on one baseline (y = 29), above all the dots,
  and centred on its dot's x. Where two dots sit together, only the hovered one, or else the most advanced, shows its
  label.
- **Queued PRs** (running, not started): a hollow grey circle at the top of the slope.
- **Runway top**: y = 52.

Quiet (36 pt):

- **Slope**: from (0, 6) to (268, 30). Runway top: y = 30.
- **Empty and first run**: the slope is dashed (4 pt dash, 4 pt gap) at 50%, and the runway is empty.
- **Failed**: a red cross, 10 pt, on the slope's end cap (centre x = 258), before the runway. It does not overlap any
  landed mark. The runway stays grey.
- **Paused**: the whole profile at 40%, and two pause bars (2 pt wide) at the runway's right end.

## 3. Rows

- Line 1: the title, 13/500 ink, full row width, one line, truncated. The full title is in the tooltip. A chevron sits
  on line 1 at the far right, at 50% opacity on hover, in space the title leaves free. Nothing moves on hover.
- Line 2: left, "#1212 · omar", 12/400 secondary. A carried-over row adds " · from 10:12 AM" (the time in the user's
  locale). Right, the status: in flight, a four-dash meter 36 pt wide, then the label, then the mark.
- Line 3, changes rows only: the review's reason, 12/400 in the changes text colour, one line.
- Height: 44 pt (two lines) or 60 pt (three lines). Heights are fixed; a row does not grow.
- Order within each repo: changes, no result, in flight, approved, skipped. In flight, the latest stage first, then
  queued. Ties go by PR number, highest first.

### Status idiom

One idiom per row: a 7 pt mark in the profile's shape, then a 12/500 label in the state's text colour. There are no
pills and no chip backgrounds.

| State | Mark | Label | Label colour |
|---|---|---|---|
| changes | triangle | Changes | changes text (#8A5300 / #FFC966) |
| approved | circle | Approved | approved text (#1B6B3F / #7EE0A6) |
| skipped | dash | Skipped | secondary |
| no result | hollow circle | No result | secondary |
| in flight | hollow blue circle | the stage word: Gather, Review, Check, Land | doing text (#0060CC / #4DA3FF) |
| queued | hollow circle | Queued | secondary |

In-flight rows keep the four-dash meter before the label: done dashes ink at 35%, the current dash the system blue,
future dashes ink at 12%. The current dash is the brightest in both modes.

When paused, status labels and marks render at 60% opacity. Carried-over rows dim both the mark and the label to
tertiary, so a grey mark never sits beside a green label.

Hover: the row fills with ink at 5%, inset 8 pt.

## 4. Layout

- 16 pt inset on the left, right and top of the popover.
- Group label: 11/600 secondary, 20 pt above and 6 pt below. A 1 pt rule in ink at 8% sits between groups.
- With a single repo there is no group label.
- The popover hugs its content: the footer row is 44 pt, with 12 pt above it and 12 pt below it. No blank ground
  below the footer in any state.

## 5. Footer

The primary button on the left (small, bordered unless noted):

| State | Button |
|---|---|
| running | "Stop" (asks first; reviews already posted stay posted) |
| paused | "Resume", prominent (`.borderedProminent`) |
| first run (no run yet) | "Edit repos…", prominent. Opens the config in the default editor, creating it from the commented template if missing |
| otherwise | "Run now" (disabled when the schedule is not installed) |

On the right, the ellipsis menu: a disabled "Glidepath 1.0.3" title (or "Update to 1.1.0…" when a newer release is out),
Pause or Resume, Open log, "Check for updates…", the last run's tokens (disabled), Open at login (a native checkmark),
and Quit Glidepath (⌘Q).

When a newer release is out, one line sits above the footer: "Glidepath 1.1.0 is available" (12 pt, 500) with "What's
new" in the doing colour, which opens the release page. While an update runs it reads "Updating to 1.1.0…" with a small
indeterminate spinner. A failed update reads "Update failed · Open log" in the error colour. A manual check reports its
result on this line for 4 s: "You're on the latest version", the available line, or "Couldn't check for updates".

## 6. Colour and type

- Ink #111 / #F2F2F2. Secondary #5C5C5C / #A8A8A8. Tertiary #6B6B6B / #8E8E8E.
- Changes text #8A5300 / #FFC966. Approved text #1B6B3F / #7EE0A6. Doing text #0060CC / #4DA3FF. Error #C4242A / #FF6B6B.
- The doing mark is the system blue.
- Type: 11, 12, 13 and 17 point, weights 400, 500, 600 (and 600 for the group labels).
- Text is at least 4.5:1 on the grounds, marks at least 3:1. No gradients in the popover.
- In a failed run, only the headline, "Open log" and the cross are red.

## 7. Menu bar glyph

18 pt canvas, centred on (9, 9). Template images only (no colour). The glyph is the app icon's mark in miniature: a
disc of horizontal stripes (radius 8 pt, five stripes 1.6 pt tall at a 3.2 pt pitch, centred on y = 9, each clipped to
the disc), with a 3 pt rounded slot cut in from the upper left at 24 degrees. The slot ends at the touchdown point
T = (11.5, 6.5), where the dot sits (radius 1.1 pt). The slot is cut with a clear compositing operation.

| State | Glyph |
|---|---|
| idle | disc, slot and dot at T |
| running | disc and slot; the dot moves from where the slot meets the disc edge to T as the sweep progresses (10 fps), then the active count |
| changes waiting | idle mark, then the count of PRs needing changes |
| paused | stripes only, at 50% ink: no slot, no dot |
| failed | idle mark with a 4 pt cross (1.5 pt strokes, round caps) centred on T in place of the dot; the slot stays cut |

Counts are 12 pt semibold, the same in every state. Changes waiting clears when the popover opens after the run ends.

An update on offer adds a 3 pt dot centred at (16, 16), at the top right, in template ink. It appears in every state
and clears when the app is on the latest release.

## 8. App icon

The app icon is the brand artwork in `assets/brand/`: a disc of white horizontal stripes on a near-black rounded tile,
with a slot cut in from the upper left and an amber (#FFB020) touchdown dot at its end. `icon.png` (1024 px, the full
art) and `icon-small.png` (1024 px, the simplified art) are the sources. `assets/brand/gen.py` regenerates the SVGs and
the wordmark, social and tile art. `make-app.sh` builds the iconset with `sips`: 16 and 32 pt, and their @2x, from the
simplified art; 128, 256 and 512 pt, and their @2x, from the full art. `iconutil` packs the `.icns`, and `codesign`
signs it ad hoc. The menu bar glyph is drawn in code (section 7) and does not use the artwork.

The icon sheet (`docs/shots/icon.png`) shows every size of the built iconset, with 512 and 256 @2x shown at 256 px so
the sheet fits. The labels give the size.

## 9. Gaps and deviations

- **Running height**: 640 pt measured (1280 px at 2x, `docs/shots/running-light.png`). Pass 3 measured 644 pt; the
  quiet profile is 36 pt and the header is unchanged. The brief's earlier target of under 500 pt is not met. Seven rows
  across two repos plus two group labels need about 340 pt of list alone. Options: cap the list with the scroll view
  (already in the build), drop the 20 pt group space, or make changes rows 44 pt.
- **Pause glyph**: the 12 pt pause glyph before "Paused" is not in the build. The headline is in the changes colour
  without it.
- **Carried-over rows**: after a failed sweep, a PR with no verdict in the run takes the newest earlier verdict and the
  start of the run that decided it. The row shows "from 10:12 AM" on line 2.
- **Popover height**: the popover is capped at 640 pt. Past that, the list scrolls.
- **Not in this design**: the bold landing moment beyond the slide, and the appearance of the mark, wait for v1.1.

## 10. Behaviour kept from earlier passes

- A landed PR animates once while the popover is open. A mark that was already there when it opened does not.
- Reduced motion turns off every slide and pulse. State changes are immediate.
- Snapshot mode (`glidepath --snapshot <dir>`) renders the states above from fixtures, light and dark, plus the glyph
  strip. `glidepath --hero-gif <path>` writes the README hero as a looping GIF, with injected time.
