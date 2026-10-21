# Glidepath: design

The menu bar app shows a sweep as an approach profile. Each PR flies down a glide slope until it lands on
the runway with a verdict. Left to right is progress, so the header needs no legend beyond its four stage
ticks. The screen answers "do I need to act?" first.

This document is the final design. It replaces design pass 1 and the radar that pass 1 described.

## 1. Header: the approach profile

Full content width (328 pt, x = 16 to 344), 64 pt tall, at the top of the popover.

- **Stage ticks**: four labels, 11/400 secondary, above the slope: `gather` at x = 0, `review` at x = 88,
  `check` at x = 176, `land` at the runway (x = 268). Their baseline is at y = 10.
- **Glide slope**: one 1.5 pt line in secondary colour, from (0, 18) to (268, 50). The slope starts below
  the tick labels so the labels stay clear of it. (Pass 2 said y = 6; the labels need the room.)
- **Stage columns**: stage n (1 to 4) is centred at x = (n - 0.5) / 4 * 268.
- **Active PRs**: an 8 pt circle in `doing` (system blue) on the slope at its stage column. PRs on the same
  stage spread 10 pt apart along the slope. The most recently active PR gets a 2 pt halo ring.
- **Queued PRs** (running, not started): a grey circle at the top of the slope.
- **Runway**: 60 pt by 4 pt at x = 268 to 328, y = 52 to 56, in ink at 25%.
- **Landed PRs**: 8 pt rounded squares (radius 2) sitting on the runway, packed left to right in list order.
  Changes are amber (#E5A000), approved green (#30A46C), skipped and no-result grey. With more than six, the
  squares shrink to fit the runway.
- **Motion while running**: each active circle slides along the slope by at most 6 pt and back, on a 4 s
  ease-in-out loop. **On landing**: the circle slides down the rest of the slope and onto the runway in 0.7 s
  with an ease-out curve, and turns into its square in the verdict colour. Reduced motion: final positions
  only, no slides.
- **Idle**: slope and runway drawn, last sweep's squares on the runway, no circles.
- **Paused**: slope and runway at 40% opacity, two 2 x 8 pt pause bars at the start of the slope.
- **Failed**: runway in the error colour at 60%, with a small x at its left end.
- **Hover**: hovering a row rings its circle or square (12 pt ring in `doing` or the verdict colour), and
  hovering a mark highlights its row.

## 2. Header text

Left-aligned at x = 16, three lines, no separator dots at line ends. The first line is 17/600 ink, unless
noted; the second 13/400 ink; the third 12/400 secondary.

| State | Line 1 | Line 2 | Line 3 |
|---|---|---|---|
| running | amber dot, then "2 need changes"; with none: "Reviewing 3 PRs" | "3 reviewing · 4 of 7 landed" | "Started 10:12" |
| idle, changes | amber dot, "2 need changes" | "Last sweep 10:12 · 7 PRs" | "Next sweep 13:00, in 2 h 41 min" |
| idle, clear | "All clear" | "Last sweep 10:12 · 7 PRs" | "Next sweep 13:00, in 2 h 41 min" |
| paused | "Paused" | "Scheduled sweeps are skipped" | "Since 10:35" |
| failed | "Last sweep failed" (error colour) | "Couldn't finish the review. Showing results from 09:12." | "Open log" link, error colour, underlined |
| empty | "No open PRs" | "Watching 2 repos" | "Next sweep 13:00, in 2 h 41 min" |
| first run | "Ready for the first sweep" | "Sweeps run at 07:00, 13:00 and 19:00" | "Next at 13:00, in 2 h 41 min" |
| not scheduled | "Not scheduled" (amber) | "Run `glidepath init` to set it up" | none |

Tokens leave the header. They go into the ellipsis menu as a disabled item: "Last run: 1.2M tokens".

## 3. Status column: one mark per row

- **Finished rows**: one chip, 11/600 sentence case, 20 pt tall, 8 pt horizontal padding, radius 4, no border,
  no rotation.
  - Changes: text #7A4B00 on #FBEBC8 (light); #FFC966 on #3A2A0C (dark).
  - Approved: text #1B6B3F on #DDF3E4 (light); #7EE0A6 on #12301F (dark).
  - No result (a failed run, or a PR the run never reached): text #555 on #EBEBEB (light); #BBB on #333 (dark).
  - Skipped: no chip. Plain 12/400 secondary text with the reason, as "Draft, skipped".
- **Active rows**: the stage word in the `doing` text colour, and below it a four-dash meter: done dashes ink
  at 60%, the current dash in `doing`, future dashes #C4C4C4 (light) or #555 (dark). Finished rows have no meter.
- **Queued rows** (running, not started): "Queued" in secondary.
- The status column's width is intrinsic. The title column takes the rest.

## 4. Rows

- Line 1: the title, 13/600 ink, up to two lines (13 pt type, 16 pt leading). The row grows from 52 pt to
  fit a second line. Titles do not truncate to one line.
- Line 2: `#1125` in SF Mono, then the author, 12/400 secondary.
- Changes rows: line 3 is the review's reason, 12/400, in the changes text colour, one line. The full text is
  in the tooltip.
- Approved rows: no reason line.
- Rows are ordered: changes, then in progress (and queued while running), then approved, then skipped, then
  no result. Ties go by PR number, highest first.

## 5. Grid

- Symmetric 16 pt gutters: every element lives between x = 16 and x = 344. That covers the header, rows,
  chips, footer and ellipsis button.
- The hover highlight spans x = 8 to 352 with radius 6.
- Hover chevron: it fades in at x = 344, and the status column moves in to make room, so there is no dead strip.
- Repo groups: a label at 11/600 secondary (dark #9A9A9A), 20 pt above and 4 pt below. A 1 pt rule in ink at
  8% spans x = 16 to 344, between groups only.

## 6. Footer

- Left: a bordered button. "Run now" when idle, empty, first-run or failed; "Resume" while paused; "Stop" while
  running. Stop asks first: "Stop the current sweep?" with "Reviews already posted stay posted."
- Right, aligned to x = 344: the ellipsis menu. Pause (or Resume), Open log, the last-run tokens info item, a
  divider, Open at login (a native checkmark), a divider, and Quit Glidepath (⌘Q).
- Run now asks first when a repo posts reviews (`posting = "review"`).

## 7. Colour and type

- Type: four sizes (11, 12, 13, 17) and weights 400 and 600. The stamp and chips use 11/600.
- Text is at least 4.5:1 on the grounds; marks are at least 3:1.
- `doing` text: #0060CC (light, 5.3:1), #4DA3FF (dark). `doing` marks: the system blue.
- Secondary: #6B6B6B (light), #9A9A9A (dark). Never lighter.
- Grey marks: #767676 (light), #8A8A8A (dark).
- Verdict marks on the profile are the same in both modes: amber #E5A000, green #30A46C.
- No gradients anywhere.

## 8. Menu bar glyph

18 x 18 pt, a template image unless noted. The glyph echoes the profile: a short slope descending to a runway bar.

| State | Glyph |
|---|---|
| idle, clear | slope and runway |
| running | slope, runway, and a dot moving down the slope (10 fps), then the count of active PRs |
| changes waiting | slope and runway with the count of changes in amber (#C77700 on a light bar, #FFB000 on a dark one). Not a template image. Cleared when the popover opens after the run ends |
| paused | runway and two pause bars |
| failed or not scheduled | a triangle with "!" at 1.5 pt stroke |

## 9. App icon

A squircle on a flat night blue (#0E2236, no gradient). One glide slope in #4DA3FF descends from the top left to
a runway of three short white dashes at the lower right. One amber square is landed on the runway. It must read
at 16 pt; the slope and the square are drawn heavy enough to do so. `docs/shots/icon.png` shows it at 512 and at
32 and 16 pt.

## 10. Behaviour kept from earlier passes

- Opening the popover after a run ends clears the menu bar's "changes waiting" mark.
- A stamp or square that lands while the popover is open animates once. A stamp that was already there when the
  popover opened does not.
- Reduced motion turns off every slide, pulse and settle. State changes are immediate.
- Snapshot mode (`glidepath --snapshot <dir>`) renders the states in this document from fixtures, light and
  dark, plus the menu bar strip and the icon.

## 11. Not in this design

The bold landing moment beyond the slide and the square's appearance waits for v1.1.
