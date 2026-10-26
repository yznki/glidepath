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
| 1.7 | live: scratch PR #2 bot threads: agree fixed+replied+resolved, disagree → call → `tend reply` posted+resolved, 15k tokens, CI green | done | |
| 1.7 | Sonnet review: 15 findings (handled asks, per-PR lock + merge, double-post guard, ReplyGuard bypasses, pushback untrusted, Bot typename, settled reviews + seeding, noise threads, pushed sha in reply, downgraded verdicts, discard → calls, dropNeeds scope, council fail-closed, grammar) all fixed, 479 pass | done | 9e73d65 438172a |
| 1.7 | live re-verify: new bot thread fixed, reply sha = pushed head 0909d35, bot plain comment ignored, second check idle, CI green | done | |
| 1.7 | released 1.7.0: PR https://github.com/yznki/glidepath/pull/11, release https://github.com/yznki/glidepath/releases/tag/v1.7.0, tap 1516b88, sha256 a6428754…, snapshots /tmp/gp-1.7 | done | 15c149c |
| 1.8 | branch sdlc-1.8 from main 084bc94; core: merge setting, Landing, MainWatch, TendLanded (495 pass) | done | 9d61ad6 |
| 1.8 | CLI: land step, `tend land/revert`, conflict rounds, main watch, revert PRs, skill Conflicts (502 pass) | done | 8f58d78 be8c8dd 124aa2c |
| 1.8 | App: land/revert rows, notifications, landing glide, drawer markers, Landing setting; snapshots /tmp/gp-1.8 | done | a733f64..9234ca8 |
| 1.8 | live: scratch #3 landed (merge f1e5ff1), #4 retargeted with approval KEPT, stack-a deleted, #4 landed next check; #5 conflict resolved + pushed (15k tokens); watch → ok. Bugs: conflict check counted clean-merged files (fixed 22c0b31); revert of #3 conflicted with #4 (expected; abort + message 0418fae) | done | |
| 1.8 | live re-check: #2 conflict resolved + pushed (not landed, unapproved, 13k tokens); revert of #4 opened scratch #6 (closed) | done | |
| 1.8 | Sonnet review: 14 findings (watch verdict conclusions + completion + reruns, branch delete safety, forks, fresh re-read before land, unanswered asks, held merge push no rebase, landable carry-over, MERGED confirm, rebase-method revert, revert branch reuse, caption, watch timeout, merge message) — 13 fixed, explicit-off→ask kept as decision; 504 pass | done | 57a5a26..287bb12 |
| 1.8 | live: scratch #7 landed, land-e deleted, main green watch | done | |
| 1.8 | released 1.8.0: PR https://github.com/yznki/glidepath/pull/12, release https://github.com/yznki/glidepath/releases/tag/v1.8.0, tap bffe90a, sha256 7f35c047…, snapshots /tmp/gp-1.8 | done | 4fa784c |
| 1.9 | branch sdlc-1.9 from main 9b11183; core: config, Linear, Nudge, Describe, Briefing, consolidation, self asks (542 pass) | done | 4bb7f71 |
| 1.9 | CLI: Linear key via /usr/bin/security (stdin), self-review, description upkeep, nudges + `tend ping`, Linear comments, briefing, consolidation (554 pass) | done | 2e0f87d..8f65bfa |
| 1.9 | App: briefing card, Ping rows, drawer self-review + changes, Linear row, Settings → Playbook; snapshots /tmp/gp-1.9 | done | 12661af c7feb69 66b23b9 aefa056 |
| 1.9 | live: scratch #8 self-review (nothing posted) → finding fixed + pushed a7ae02a (13k tokens), PR body block added with original text kept, briefing written; Linear key round trip on a temp keychain; curl header file verified | done | |
| 1.9 | Sonnet review: 14 findings (self-review vs run.lock, failure retry, double count, symlink token undercount, review budget cap, child timeout, body-only findings, state merge + ping lock, unbalanced markers, consolidation safety, playbook editor identity, Linear/Ping guards, self-review switch, rounds count) all fixed, 570 pass | done | |
| 1.9 | live re-check: draft→ready re-runs self-review, kind self-review, nothing posted; token count still 0 → found Foundation strips /private again, fixed with realpath | done | 324ad81 |
| 1.9 | released 1.9.0: PR https://github.com/yznki/glidepath/pull/13, release https://github.com/yznki/glidepath/releases/tag/v1.9.0, tap b3d594c, sha256 1af9ecbc…, snapshots /tmp/gp-1.9 | done | f2a0d98 |
| 1.10 | branch sdlc-1.10 from main 1585853; core: Split plans, validate, branches, stack table, skill split.md (588 pass) | done | ae3f8e0 |
| 1.10 | CLI: plan session (Opus, read-only), auto trigger, `tend split plan/build/keep`, per-part checks, chained PRs, autopilot council (597 pass) | done | 52fcb01 ab8d2c7 19731a3 |
| 1.10 | App: split needs, drawer Split…, builder overlay (drag + move menu, live validation); snapshots /tmp/gp-1.10 | done | 8817493..c15e215 |
| 1.10 | live: scratch #9 → plan 3 parts (8.7k tokens) → build #10→#11→#12 chained, stack tables, #9 drafted + comment, CI green (31k tokens); all closed after. Gap: per-part check recorded once | done | |
| 1.10 | Sonnet review: 17 findings (app timeout, moved base, partial-build cleanup, checks by exit code, head re-read, literal pathspecs, edits via CLI, plan/build guards, staleness, one auto plan per PR, council run record, manual vs auto council, tendable checks, public text limits, -z paths, source off after build) fixed, 605 pass | done | c65892e 9ac79e8 c232017 |
| 1.10 | live re-check: scratch #13 → plan 3 parts → edited parts via `--parts` → #14→#15→#16, checks by exit code ok, source drafted + off; 37k tokens; all closed | done | |
| 1.10 | released 1.10.0: PR https://github.com/yznki/glidepath/pull/14, release https://github.com/yznki/glidepath/releases/tag/v1.10.0, tap 7faa5f6, sha256 cefe50a2…, snapshots /tmp/gp-1.10 | done | cfba214 |

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

- 1.8: `merge` parses off; turning tending on in Settings writes `merge = "ask"` (also when it was an explicit off).
- 1.8: main watch with no check runs yet on the merge commit counts as pending, never green.

- 1.8: retargeting a stacked child to main kept its approval on the scratch repo (no rulesets there); Sager's
  rulesets were not tested (build never touches Sager repos).
- 1.8: a child whose retarget fails keeps the merged branch alive (deleting it would make GitHub close the child).

- 1.8: merge queues: if `gh pr merge` only queues the PR, Glidepath records nothing and tries again next check; a
  PR the queue lands later is not watched. Neither scratch nor (as far as known) Sager uses merge queues.
- 1.9: Linear key lives in the Keychain via `/usr/bin/security` (key passed on stdin), so the launchd job can read it
  after brew upgrades without a prompt.
- 1.9: turning tending on writes `self_review = true` (also over an explicit false), like `merge = "ask"`.

- 1.9: Ping and nudges were not tried live (the scratch repo has no second human reviewer; a ping would notify a real
  person). Linear posting was not tried live (only Sager's Linear exists); mechanism parts verified locally.
- 1.9: review token counts were 0 for any clone path under /tmp (symlink to /private/tmp); fixed in 1.9.0. Yazan's
  clones are under his home, so his past counts were not affected.

- 1.10: split checks run in the Claude sandbox (repo commands are untrusted); Glidepath reads each command's exit
  code from a file the shell writes. Autopilot builds only with verified playbook commands. Automatic planning
  happens at most once per PR; Split… replans.

## Open issues

- (closed) gh token lacked `workflow` scope; Yazan added it. Scratch repo now runs a real Actions workflow ("Unit tests",
  npm test). Fake CI retired.
