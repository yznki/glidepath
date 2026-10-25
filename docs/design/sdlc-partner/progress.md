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
| 1.6 | Sonnet review: 15 findings (worktree .git redirect, sandbox denyRead, toggle no-op, rerun/discard dead ends, lost updates, closed-PR cleanup, PushGuard path parse, commit attribution strip, playbook sanitize, approval w/o required reviews, hold reset, needs carry-over, run-file reads, account reselect) | done (441 pass) | 66126de 680056f |
| 1.6 | live re-verify after fixes: round fixed off-by-one (d958cdf), evidence has ##[error] no ANSI, .git link ok, no attribution, CI green, 18k tokens | done | |
| 1.6 | CHANGELOG + README tending section | done | |
| 1.6 | released 1.6.0: PR https://github.com/yznki/glidepath/pull/10, release https://github.com/yznki/glidepath/releases/tag/v1.6.0, tap ea71232, sha256 1668ed4b…, snapshots /tmp/gp-1.6 | done | d232213 |
| 1.7 | branch sdlc-1.7 from main 3b3fa4a, notes `notes/1.7.md` | done | |
| 1.6 | real Actions live check: tend fixed mul on PR #1 (8f8691a, run green, 15k tokens); job-log fetch was empty (gh refuses escape sequences) → fixed with --allow-escape-sequences + ANSI strip, verified `##[error]` present; `gh run rerun --failed` works (attempt 2 started, cancelled); ~4 Actions minutes | done | |
| 1.7 | core: threads, reply guard, full fingerprint, council/lessons pure parts (458 pass) | done | 8398513 |
| 1.7 | CLI: replies/resolve, threads evidence, council runner, pushback + edit lessons, `tend reply/dismiss` (467 pass) | done | fa20bad cbb406a |
| 1.7 | App: call rows + edit overlay, verdict lines, council cards, disagree setting; snapshots /tmp/gp-1.7 | done | aa537db 60d5beb f6f9ad9 |
| 1.7 | teammate Glidepath marker `<!-- glidepath:review -->` on posted reviews; bot plain comments never trigger | done | 67b2759 |
| 1.7 | scratch Bot workflow (bot.yml: comment/line/approve/changes via GITHUB_TOKEN; Actions may approve) | done | scratch 78cdac6 |
| 1.8–1.10 | build notes written | done | 0d71d00 69b7ae0 c717454 |

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

- 1.7: plan says Yazan's config gets `disagree = "reply_resolve"`; his config is never edited by the build, so he sets
  it himself (Settings → Tending → When Glidepath disagrees → Reply and resolve).
- 1.7: a teammate's Glidepath is recognised by a hidden `<!-- glidepath:review -->` marker that 1.7 now appends to
  every posted review body and inline comment.

## Open issues

- (closed) gh token lacked `workflow` scope; Yazan added it. Scratch repo now runs a real Actions workflow ("Unit tests",
  npm test). Fake CI retired.
