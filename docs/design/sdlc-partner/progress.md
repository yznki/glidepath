# SDLC partner build progress

Resume here after a compaction. One line per step; decisions and open issues below.

## Status

| Phase | Step | Status | Commit |
|---|---|---|---|
| 1.6 | branch sdlc-1.6, build design `notes/1.6.md` | done | |
| 1.6 | H1 core: config, usage guard, push guard, approach, tend state, autopilot, playbook + tests (423 pass) | done | 323f278 25b745c |
| 1.6 | H2 CLI: tend command (CLI/TendCommand.swift), rounds, launchd job, review stream-json (430 pass) | done | ce59761 2e92169 c247736 |
| 1.6 | live check: scratch PR #1 broken add → tend fixed + pushed ff37538, CI green, 30k tokens; rerun idle; hands-off label → no round. Found: usage events nest under unifiedWindows (fixed) | done | |
| 1.6 | H3 App: Approach section, chart, drawer, popover, settings (isolated worktree) | in progress | |

## Decisions (Yazan should know)

- `max_usd_per_session` is whole dollars: the TOML reader has no floats.
- Every check counts as required for the CI gate (GraphQL `isRequired` needs a per-PR argument).
- Usage guard has no per-task estimate yet: it refuses at `100 - reserve` utilization; estimates once History calibrates.
- Quiet-hours question is in Settings → Tending, not onboarding (tending is off for new installs anyway).
- Autopilot toggle only writes `autopilot = true`; `Autopilot.swift` treats push/disagree/merge as their autopilot
  values at decision time instead of rewriting those keys.
- Turning tending on (Settings) writes `advisor = "opus"`; push stays `until_approved` until the user picks.
- `claude_config_dir` is top level: the separate account runs reviews and tending.
- Playbook commands record count and date, not duration.
- Tend sessions are contained by the Claude Code sandbox + scoped Read/Edit allowlist; no bash-guard hook (that guard
  only allows glidepath subcommands, which a fix session can't work with).
- Repo git hooks never run: every tend git call uses `core.hooksPath=/dev/null` (hooks would run outside the sandbox).

## Open issues

- none yet
- gh token lacks `workflow` scope (re-auth needs a browser), so the scratch repo has no Actions workflow. Live CI
  checks use a local fake CI (`/tmp/gp-fakeci.sh`: runs `npm test` per head, posts commit status "Unit tests").
  Job-log fetching and `gh run rerun` stay unverified live; covered by unit tests only. Fix: `gh auth refresh -s workflow`.
