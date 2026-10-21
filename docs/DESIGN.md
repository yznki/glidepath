# Review Radar: design

The menu bar app shows the scheduled review run as a radar. The same binary runs the CLI.

## Concept

- Each PR is a flight strip on an approach radar. A run is one sweep.
- A blip's distance from the centre is its stage: gather at the rim, post at the centre.
- Posted PRs are stamped with their verdict (APPROVED, CHANGES, SKIPPED).
- Glance test: is it running, how far along, what came out.

## Data

Source of truth: `~/.local/state/review-radar/runs/<id>.json`, pointed to by `current`. The
app watches the state folder with a DispatchSource and reloads on each write. No polling.

Running means the run is unfinished and its lock file is held. A crashed run never shows as running,
because the kernel releases the lock when the process exits.

Schedule times come from `config.toml`. "Next sweep" is the first scheduled time after now.

## Art direction

- Palette, semantic so it works in light and dark: ground = popover material; ink = primary;
  muted = secondary; scan = teal `#2BB3A3`; approve = `#30A46C`; changes = amber `#E5A000`;
  skipped = secondary.
- Type: system text, rounded semibold for the header count, monospaced for `#n` callsigns and digits.
- Shape: 10 pt radius on strips, 4 pt on stamps, capsule rails.
- Motion: one spring, `response 0.45`, `damping 0.86`. Sweep is 3 s per turn while running and 10 s
  when idle. Reduced motion stops the sweep and the stamp scale.

## Layout (360 pt popover)

- Header: radar (84 pt) with the state text beside it.
- Last-sweep line, then strips grouped by repo, scrolling after six rows.
- Footer: Run now, Pause/Resume, Log, Open at login, Quit.

A repo whose run failed shows its error in amber under its name.

## Constraints

- No macros. Command Line Tools must build the app, and they cannot load SwiftUI's macro plugins,
  so `@State` is replaced by a small `ObservableObject` held in `@StateObject`.
- Offscreen snapshot rendering (`--snapshot <dir>`) draws fixtures. ImageRenderer does not run `onAppear`
  reloads and draws AppKit checkboxes as a prohibition sign, so the snapshot path uses text for those.
