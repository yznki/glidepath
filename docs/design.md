# Glidepath: design

The menu bar app shows a sweep as an approach profile. Each PR flies down a glide slope to a runway and lands with
a verdict. Left to right is progress. The popover answers "do I need to act?" first.

This is the final design (design pass 3 wins where earlier passes conflict). Two places where the build does not
meet the brief are listed at the end, with the reason.

## 1. Header

Every header line starts at x = 16. No coloured dots before a headline.

| State | Line 1 (17/600) | Line 2 (13) | Line 3 (12, tertiary) |
|---|---|---|---|
| running | "Reviewing 3 of 7" (active of total) | "2 need changes" in changes text (13/500); with none, "4 landed" | "Started 10:12 AM" |
| idle, changes | "2 need changes" | "Last sweep 10:12 AM · 7 PRs" | "Next sweep 1:00 PM, in 38 min" |
| idle, clear | "All clear" | "Last sweep 10:12 AM · 3 PRs" | "Next sweep 1:00 PM, in 38 min" |
| paused | "Paused" | "Last sweep 10:12 AM · scheduled sweeps skipped" | "Paused since 10:35 AM" |
| failed | "Last sweep failed" (error) | the one-line reason in plain words, e.g. "The review agent stopped early (exit 1)" | "Retrying at 1:00 PM · Open log" (Open log 13/500, error colour, no underline) |
| empty | "No open PRs" | "Watching 2 repos · last sweep 10:12 AM" | "Next sweep 1:00 PM, in 38 min" |
| first run | "Ready for the first sweep" | "Reviews every open PR in 2 repos" | "First sweep at 1:00 PM" |
| not scheduled | "Not scheduled" (changes text) | "Run `glidepath init` to set it up" | none |

Times use the user's locale (`Date.FormatStyle` `.hour().minute()`), never a hard-coded 24-hour format.
Tokens are not in the header. They are in the ellipsis menu as a disabled item.

## 2. Approach profile

- **Full** (328 x 64 pt) only while a run is in progress.
- **Compact** (328 x 32 pt) when idle, paused or failed with a last run: the runway and the landed marks, with a short
  lead-in of slope. Hidden when there is no run yet, and in an empty run.
- **Slope**: 2 pt line, #3A3A3C (light) / #D0D0D0 (dark). It starts at (0, 18) and runs to (268, 50), below the stage
  labels, so the labels stay clear of it (see section 9).
- **Stage labels**: "gather", "review", "check", "land" at x = 0, 88, 176 and 268. 11/500 tertiary, above the slope.
- **Stage columns**: stage n is centred at x = (n - 0.5) / 4 * 268.
- **In-flight PRs**: a 10 pt circle in the system blue, spread 11 pt apart along the slope within their stage. Each
  is labelled with its number ("#1113", 11/500 tertiary), above the dot, or below it when it sits too high to clear the
  stage labels. A label that would collide with its neighbour is hidden, unless its PR is hovered.
- **Queued PRs** (running, not started): a hollow grey circle at the top of the slope.
- **Landed marks** (9 pt), on the runway in list order, shape-coded and coloured:
  - approved: filled circle, #1F8A52 (light) / #3DD68C (dark);
  - changes: filled triangle, #B86E00 / #FFB020;
  - skipped: dash 9 x 3 pt, #6B6B6B / #9A9A9A;
  - no result (finished without a verdict): hollow grey circle.
  Past five landed marks they shrink so they still fit the runway.
- **Runway**: 60 x 4 pt at x = 268 to 328, in ink at 25%. In a failed run it is the error colour at full opacity, with a
  9 pt cross at its left end.
- **Paused**: the slope at 40%, and two pause bars at the runway's right end.
- **Motion** (running only): each in-flight circle slides along the slope by at most 6 pt and back, on a 4 s ease-in-out
  loop. On landing, the circle slides onto the runway in 0.7 s with an ease-out curve and becomes its mark. Reduced
  motion: final positions only.
- **Hover**: one 2 pt ring in the mark's colour, 4 pt outside the mark. No second ring.

## 3. Rows

- Line 1: the title, 13/500 ink, one line, truncated. The full title is in the tooltip.
- Line 2: "#1212 · omar", 12/400 secondary.
- Changes rows only: line 3 is the review's reason, 12/400 in the changes text colour, one line.
- Height: 44 pt (two lines) or 60 pt (three lines). Heights are fixed; a row does not grow.
- Order: changes, then in progress (and queued while running), then approved, then skipped, then no result. Ties go by
  PR number, highest first.

### Status idiom

One idiom per row, in a fixed 84 pt right-aligned column: a 7 pt mark in the profile's shape, then a 12/500 label in the
state's text colour. There are no pills and no chip backgrounds.

| State | Mark | Label | Label colour |
|---|---|---|---|
| changes | triangle | Changes | changes text (#8A5300 / #FFC966) |
| approved | circle | Approved | approved text (#1B6B3F / #7EE0A6) |
| skipped | dash | Skipped | secondary |
| no result | hollow circle | No result | secondary |
| in flight | hollow blue circle | the stage word: Gathering, Reviewing, Checking, Landing | doing text (#0060CC / #4DA3FF) |
| queued | hollow circle | Queued | secondary |

In-flight rows keep a four-dash meter under the label: done dashes ink at 35%, the current dash the system blue, future
dashes ink at 12%. The current dash is the brightest in both modes.

Hover: the row fills with ink at 5%, inset 8 pt. A chevron sits at 50% opacity in the reserved strip at the far right.
Nothing moves on hover.

## 4. Layout

- 16 pt inset on all four sides of the popover.
- Group label: 11/600 secondary, 20 pt above and 6 pt below. A 1 pt rule in ink at 8% sits between groups.
- 12 pt above the footer row.
- With a single repo there is no group label.

## 5. Footer

A primary (bordered, small) button on the left: "Run now", "Resume" while paused, or "Stop" while running (it asks first;
reviews already posted stay posted). On the right, the ellipsis menu: a disabled "Glidepath 1.0" title, Pause or
Resume, Open log, the last run's tokens (disabled), Open at login (a native checkmark), and Quit Glidepath (⌘Q).

## 6. Colour and type

- Ink #111 / #F2F2F2. Secondary #5C5C5C / #A8A8A8. Tertiary #6B6B6B / #8E8E8E.
- Changes text #8A5300 / #FFC966. Approved text #1B6B3F / #7EE0A6. Doing text #0060CC / #4DA3FF. Error #C4242A / #FF6B6B.
- The doing mark is the system blue.
- Type: 11, 12, 13 and 17 point, weights 400, 500, 600 (and 600 for the group labels).
- Text is at least 4.5:1 on the grounds, marks at least 3:1. No gradients in the popover.

## 7. Menu bar glyph

18 pt canvas, 1.75 pt round-cap strokes, template images only (no colour). The base mark is a 14 pt slope descending
left to right onto a 6 pt runway, vertically centred.

| State | Glyph |
|---|---|
| idle | base mark |
| running | base mark, a 3 pt dot moving down the slope (10 fps), then the active count |
| changes waiting | base mark, then the count of PRs needing changes |
| paused | base mark with two pause bars replacing the slope |
| failed | the system outline warning symbol (`exclamationmark.triangle`), nothing else |

Counts are 12 pt semibold, the same in every state. Changes waiting clears when the popover opens after the run ends.

## 8. App icon

A 1024 canvas, with the artwork in the 824 pt rounded-rect grid.

- Ground: a vertical gradient from #16395A (top) to #091827 (bottom). A 1 pt white (20%) highlight on the top edge, and a
  shadow of 0 / 12 / 24 black at 35%. (App icons may use depth; the no-gradient rule covers the popover only.)
- A runway in perspective along the lower third: a trapezoid #0B2135, a white dashed centreline, two rows of edge lights.
- A glide slope: a 34 px #4DA3FF line with round caps from the upper left, ending above the threshold.
- A touchdown light: a 64 px amber #FFB020 disc near the centre of the lower third, with a soft amber glow.
- At 64 pt and below, a simplified drawing: the slope and the amber light only, with thicker strokes and no runway. The
  icon sheet (`docs/shots/icon.png`) shows the full icon at 512 and the simplified one at 32 and 16 pt, each at real size
  and at 4x.

## 9. Deviations and gaps

- **Slope start**: y = 18, not y = 6. Stage labels sit above the slope, and at y = 6 the first dot's label collides with
  them.
- **Running height**: the running mock measures 644 pt, not under 500 pt. The arithmetic: header 16 + profile 64 + 12 +
  text 61 = 153; footer 12 + 44 + 16 = 72; list 7 rows (two changes rows at 60, five at 44) = 340 plus two group labels
  at 20 + 6 each and the rule. Under this spec, seven rows across two repos cannot fit in 500 pt. Options: cap the list
  with the existing scroll view (already in the build), drop the 20 pt group space, or make changes rows 44 pt.
- **Not in this design**: the bold landing moment beyond the slide and the appearance of the mark waits for v1.1.

## 10. Behaviour kept from earlier passes

- A landed PR animates once while the popover is open. A mark that was already there when it opened does not.
- Reduced motion turns off every slide and pulse. State changes are immediate.
- Snapshot mode (`glidepath --snapshot <dir>`) renders the states above from fixtures, light and dark, with the glyph
  strip and the icon sheet. `glidepath --render-icon FILE PIXELS` renders the icon for make-app.
