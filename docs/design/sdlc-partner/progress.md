# SDLC partner build progress

Resume here after a compaction. One line per step; decisions and open issues below.

## Status

| Phase | Step | Status | Commit |
|---|---|---|---|
| 1.6 | branch sdlc-1.6, build design `notes/1.6.md` | done | |
| 1.6 | H1 core: config, usage guard, push guard, approach, tend state, autopilot, playbook + tests (423 pass) | done | 323f278 25b745c |
| 1.6 | H2 CLI: tend command (CLI/TendCommand.swift), rounds, launchd job, review stream-json (430 pass) | done | ce59761 2e92169 c247736 |
| 1.6 | live check: scratch PR #1 broken add → tend fixed + pushed ff37538, CI green, 30k tokens; rerun idle; hands-off label → no round. Found: usage events nest under unifiedWindows (fixed) | done | |
| 1.6 | H3 App: Approach section, chart, drawer, popover, settings — merged (cherry-picked, stub dropped), 433 pass, snapshots /tmp/gp-1.6 | done | 330cfdf..931f56d |
| 1.6 | UI polish (compact hold, gates wording, round titles, settings rows) | done | 16ba26d |
| 1.6 | Sonnet review: 15 findings (worktree .git redirect, sandbox denyRead, toggle no-op, rerun/discard dead ends, lost updates, closed-PR cleanup, PushGuard path parse, commit attribution strip, playbook sanitize, approval w/o required reviews, hold reset, needs carry-over, run-file reads, account reselect) | fixing | |
| 1.6 | real Actions live check: tend fixed mul on PR #1 (8f8691a, run green, 15k tokens); job-log fetch was empty (gh refuses escape sequences) → fixed with --allow-escape-sequences + ANSI strip, verified `##[error]` present; `gh run rerun --failed` works (attempt 2 started, cancelled); ~4 Actions minutes | done | |

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

- Sandbox probe (2026-10-26, Claude Code 2.1.310): inside the tend sandbox `security find-generic-password -s gh:github.com`
  and `gh auth token` are both blocked (both succeed outside). Residual: registry network allowlist could carry
  data out with an attacker-supplied registry token; accepted, denyRead widened.

## Open issues

- (closed) gh token lacked `workflow` scope; Yazan added it. Scratch repo now runs a real Actions workflow ("Unit tests",
  npm test). Fake CI retired.
