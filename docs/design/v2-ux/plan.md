# Glidepath 2.0 rebuild plan

Approved by Yazan on 2026-10-26. Visual spec: the native prototype in `prototypes/v2-native/` (run `run.sh`) and its
screenshots in `prototypes/v2-native/shots/`. Behaviour and words: `spec.md` (sections 3–6a, 9). Code facts:
`code-map.md`.

Branch `v2` from `origin/main` (1.10). One PR per phase against `v2`, then `v2` into `main` for the 2.0 release.
The engine (Core, CLI, tend, review pipeline, config parsing) is kept. Only the UI layer is rebuilt.

## Hard constraints (every phase)

1. **Builds with Command Line Tools.** Homebrew compiles from source. No `@State`, `@Observable`, `#Preview` or any
   SwiftUI macro. View state uses `ObservableObject` models with `@StateObject` / `@ObservedObject`, as 1.10 does.
   The prototype uses macros; port its views, don't copy its state code. Check every phase with
   `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build` as well as the Xcode build.
2. **macOS 14 stays the minimum.** Liquid Glass APIs sit behind `#if compiler(>=6.2)` plus
   `if #available(macOS 26, *)`, with a material fallback that keeps the same layout. Test the fallback path by
   forcing it with a debug flag.
3. **Config defaults never change** (`glidepath-defaults-rule`). New-user defaults (review only, Ask first) are
   written by onboarding, `glidepath init` and the add-repo flow, not by `Config.parse`.
4. **Menu bar item is `NSStatusItem` + `NSPopover`**, not `MenuBarExtra`: the animated line made `MenuBarExtra`
   redraw every frame (100% CPU in the prototype). Idle CPU must be ~0%.
5. **One word list.** Every user-facing string lives in `App/Copy.swift`; a test greps the UI sources for the cut
   words in `spec.md` §3 and fails if any appear in a string literal.
6. **One Needs-you count**, derived once in Core, used by icon, popover, Dock badge, sidebar badge, Inbox header.
7. Every phase leaves `swift build`, `swift test` and the app runnable. Old screens are deleted in the same phase
   that replaces them, so there is never a half-old app on `v2`.

## Phases

| # | Phase | Contents | Built by | Review |
|---|---|---|---|---|
| 0 | Ground | Branch `v2`. Move design docs and the prototype onto it. Move `Presentation`, `HeaderCopy`, `Snapshot` derivations out of `App/` into `Core/` (CLI and RunDigest depend on them). Delete dead Store members (`openDashboard`, `dryStrips`, `errorText`, `setHovered`) if still unused. No behaviour change. | Haiku | build + tests |
| 1 | Model | `Core/NeedsYou.swift`: one list and count covering review ready, fix ready, reply ready, ready to merge, main broke, split proposed, stuck, waiting on reviewer. `Core/Status.swift`: the status sentence + glide state (quiet, checking, needs, problem, paused, holding back with reason). `stopAll()` stops a running check and a running tend round; Pause covers tending. Usage reading exposed for the gauge. `App/Copy.swift` with the 14 words. Unit tests for every state and the cut-word test. | Opus | Sonnet |
| 2 | Kit | `GlideLine` (all five states, idle breath, tracer, beads, break, dotted, Reduce Motion), `HoldButton` (glass fill, 0.6 s, hint on tap, keyboard), `UndoBanner`, `StatusHeader`, glass helpers with the macOS 14 fallback, graphite tint + amber token. Delete `UI/Gotham`, `Tracer`, `Glass`, old `HoldButton`, `Theme` tokens no longer used. | Opus | Sonnet |
| 3 | Menu bar | `NSStatusItem` with the line glyph (four shapes + count), `NSPopover` with smoky glass: status sentence, up to 4 Needs-you rows that open the window on that PR, "Since you last looked", footer (Ask first/Autopilot, Pause menu, window). Right-click menu: Check now, Pause ▸, Open, Settings…, Quit. Delete old `Popover`, `Popover/Card`, `MenuBarLabel`, `Profile`. | Opus | Sonnet |
| 4 | Window | `NavigationSplitView`: Inbox, PRs (Team / Your), Activity, Repos. Smoky translucent window. Glass Needs-you rows with the signature glide into Done today. Inspector: team review + findings + "Show how it got there" (the old flight recorder log, trimmed), your PR progress strip + timeline + Look after this PR, split review, stuck, ping, reply editing. Repo page with Learned and Remove (undo). Delete `Now`, `ApproachSection`, `ApproachChart`, `BriefingCard`, `Reviews`, `RunCard`, `Sidebar`, old `Repos`, `ReviewSheet`, `SplitBuilder` UI, `Controls`. | Opus | Sonnet |
| 5 | Settings | `Settings` scene with General, Schedule, Behaviour, Advanced (spec §4.4). Schedule: presets, time chips, days with a clear on state, quiet hours as time pickers, usage gauge + reserve. Behaviour: Ask first / Autopilot (hold to turn on), only the options that still apply. Delete old `Settings*`, `QuietHoursField`, `Schedule*`, dial. | Opus | Sonnet |
| 6 | Setup | Onboarding as a 3-step sheet (tools only if something is missing, repos with the two switches, done with a real first check in Ask first). Setup writers write review-only + Ask first for new users. Trust-ramp offers in the empty Inbox (Look after my PRs, later Autopilot), dismissible. Delete old `Onboarding*`, `HeroField`, `RepoPicker` UI if replaced. | Opus | Sonnet |
| 7 | Finish | Shortcuts trimmed to spec §5.8 + menus; notifications grouped (one per check, needs-you only by default); snapshot fixtures and `--snapshot` for every new screen; README and site screenshots (TODO: the README hero and menu bar images are the 1x phase-3 stills in `phase3-shots/`, and `--hero-gif` is gone; render a proper 2x hero); CHANGELOG; full Sonnet review of `v2` against `spec.md`; Yazan tries a build of `v2` on his Mac. | Haiku (mechanical) + Opus (fixtures) | Sonnet |
| 8 | Release | Only after Yazan says ship: merge `v2`, version 2.0.0, tag, Formula + tap (`release-tap`). | Haiku | — |

## Checks per phase

- Xcode build, CLT build, `swift test`, no new warnings.
- Run the app with fixtures (`--snapshot`) and look at every screen it touches; compare with the prototype shot.
- Idle CPU of the running app under 1% with the window closed and with it open.
- Grep for cut words passes.
- The live Homebrew app and Yazan's config are never touched; test with `GLIDEPATH_HOME` or a scratch config.
