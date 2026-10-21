# Glidepath design pass 1

Baseline critic score 6.3 (design 6.3, usability 6.0, creativity 6.5, content 6.5).
Target 8+. The fixes below come from the critique; the idea stays (ATC radar, PRs as flights,
verdict stamps). Rule for this pass: the screen answers "do I need to act?" first.

## Tokens (one table, light / dark)

| Role | Light | Dark | Use |
|---|---|---|---|
| ink | #111111 | #F2F2F2 | titles, headline |
| secondary | #6B6B6B | #A0A0A0 | meta lines (>= 4.5:1 on both grounds) |
| line | ink 8% | ink 10% | one header rule only |
| doing | system accent (`Color.accentColor`, blue by default) | same | in-progress phase, sweep arm, active blips |
| approve text / fill | #247B50 / #30A46C | #4CC38A / #30A46C | stamp text / blip |
| changes text / fill | #8A5A00 / #E5A000 | #F2B13C / #E5A000 | stamp text / blip / headline count |
| skipped | secondary | secondary | stamp, blip |
| error | #B42318 | #F97066 | run failed |

Every foreground: 4.5:1 for text, 3:1 for marks, on #F5F5F5 and #222 (the snapshot grounds) and on
the live popover material. No gradients anywhere, the radar included.

## Type

Four sizes, two weights: 11 (group labels, stamp), 12 (meta), 13 (row title, buttons), 17 (headline).
Weights 400 and 600 only (stamp 700 is the one exception). SF Pro; SF Mono only for `#1234` inside meta.

## Header (radar 92pt + text block, vertically centred on the radar, same grid in every state)

| State | Headline (17/600) | Sub-line (12/400 secondary) |
|---|---|---|
| running, changes so far | "2 need changes" (count in changes colour), then " · 3 reviewing" in ink | "4 of 7 landed · started 10:12 · 1.2M tokens" |
| running, none yet | "Reviewing 3 PRs" | same |
| idle, last run had changes | "2 need changes" | "Next sweep 13:00 · in 2 h 41 min" |
| idle, all clean | "All clear" | same |
| idle, no runs yet | "No sweeps yet" | "First sweep 13:00 · in 2 h 41 min" |
| paused | "Paused" | "Since 10:35 · scheduled sweeps are skipped" |
| run failed | "Last sweep failed" (error colour) | first line of the error, then "Open log" link |
| job not loaded | "Not scheduled" (changes colour) | "Run `glidepath init` to set it up" (selectable) |
| empty run | "No PRs to review" | "Checked 3 repos at 10:12 · next 13:00" |

## Radar (the signature, as an instrument)

- 92pt disc. Two rings + crosshair at 1pt, ink 18% (>= 1.6:1). No sweep wedge, no gradient.
- Sweep arm: one 1.5pt line in `doing`, 3 s/rev while running. Idle: arm hidden, rings only, blips
  breathe (opacity 0.7 to 1, 4 s) so it is alive but clearly not scanning. Paused: arm frozen at
  -45 deg at 30% opacity, blips at 50%.
- One 7pt blip per PR. Angle = fixed slot in list order (360 / n, starting at 12 o'clock).
  Radius = progress: queued on the outer ring, each phase one step inward, landed at 18% radius.
  Colour = state: `doing` while active, verdict fill when landed, secondary when skipped/dropped.
- While running, a blip brightens for 600 ms when the arm passes it (the radar afterglow, as
  opacity, not a gradient).
- Hovering a row draws a 12pt ring around its blip; hovering a blip highlights its row.
- Landing moment: when a PR gets a verdict, its blip moves to the centre (spring 0.45/0.86) and
  emits one ring ping (circle scales 1 to 2.2, opacity 0.6 to 0, 500 ms).

## Rows (fixed 52pt pitch, 16pt side gutters, one left edge)

- Sort: needs changes, then active, then approved, then skipped, then dropped; by number within.
- Line 1: PR title 13/600 ink, one line, truncates. Trailing: stamp, or phase word in `doing`.
- Line 2: `#1125` (SF Mono 12) · author · reason, 12/400 secondary, one line, truncates; full
  reason in `.help` tooltip. Trailing: the 4-segment rail, 44pt wide, 3pt tall capsules.
- Rail rule: done segments ink 60%, current segment `doing`, future ink 12%. Verdict is never shown
  by recolouring the rail; skipped/dropped rows show no rail.
- Right column fixed 72pt, right-aligned to the 16pt gutter, for both stamp and rail.
- Stamp at rest: upright, 72pt wide, 10.5/700 caps, 1.5pt border radius 3, fill = verdict fill at
  12%, text = verdict text colour. Landing: scale 1.15 to 1 and -3 deg to 0 over 140 ms, only when
  the verdict first appears while the popover is open. Reduced motion: none.
- Row hover: ground ink 5%, radius 6. A chevron.right (11pt secondary) fades in at the far right on
  hover. Click opens the PR. Keyboard: rows are buttons with a visible focus ring.
- Repo groups (only when >1 repo): label 11/600 secondary, 14pt above, 6pt below, 18pt before the
  next group. No rule lines between rows or groups.
- Tokens per row: removed (they go to the header sub-line total).

## Footer (one row, 44pt)

- Left: one bordered (`.bordered`, controlSize small) primary button: "Run now" (idle), "Resume"
  (paused), "Running…" disabled while running.
- Right: `ellipsis.circle` menu button: Pause / Resume, Open log, Open at login (native checkmark
  item), separator, Quit Glidepath (⌘Q).
- No status word in the footer. No second rule above the footer; spacing only.

## Menu bar glyph

| State | Glyph |
|---|---|
| idle, clear | ring + dot |
| running | ring + rotating arm, then count of active PRs |
| changes waiting (last run) | ring + dot with a small filled amber dot at top-right (non-template overlay), then the count |
| paused | ring with a pause mark |
| failed / not scheduled | exclamationmark.triangle |

"Changes waiting" clears when the popover is opened after the run ends.

## Not in this pass

The bold landing moment beyond the blip ping and stamp settle (menu bar pulse) waits for v1.1.
