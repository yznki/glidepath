# Glidepath as an SDLC partner

Glidepath reviews other people's PRs today. This adds the other half: it looks after your own PRs until they
are merged. It fixes failing CI, answers review comments that make sense, resolves threads, keeps branches
mergeable, and merges in the right order. Internally this is called **tending**.

Agreed in the grilling session on 2026-10-25. The phases below ship as 1.6 to 1.10.

## Principles (open source)

Glidepath is open source and meant for any developer. Every feature below has to pass these tests.

1. **A partner, not overhead.**
   - Install it, sign in to gh and claude, pick repos, and you're done. No server, no account, no config file to
     write.
   - It stays quiet unless it needs you, and everything is optional and can be turned off on its own.
2. **Cheap.** Watching is free, because Claude only runs when something changed. Each task gets the right model
   and effort, evidence is trimmed, cached commands mean no re-exploring, and every session has a hard cap.
3. **Never eats your usage.**
   - Glidepath reads your Claude plan limits: the 5-hour and weekly windows.
   - It keeps a reserve for you, set by `usage_reserve`, default 40% of each window. Glidepath never spends into
     that reserve.
   - Heavy work waits for your quiet hours.
4. **Safe defaults for strangers, autopilot for people who opt in.**
   - New installs start conservative: drafts, ask before merging, autopilot off.
   - Nothing about one user's setup is baked in.
5. **Portable brain.** The token-saving style and the rules live in Glidepath's own skill text. It doesn't
   depend on any plugin the user may or may not have.

## Facts this design rests on (Sager)

- `main` rules:
  - Stale approvals are dismissed on push, and the last push needs approval from someone other than the pusher.
  - Every review thread must be resolved.
  - A code owner must review.
  - 4 required checks: Unit Tests and Coverage, Secret Scan, Browser E2E, Required Verification.
  - Branches don't have to be up to date before merging.
  - Merge, squash and rebase are all allowed.
- So a push to an approved PR cancels its approval, and a teammate has to approve again.
- Feature branches (stack bases) have no rules.
- Auto-merge is off and there is no merge queue.
- Merges into `main` are merge commits.
- Yazan works in stacks. Example: the Notification center, #1301 into main, then #1302 on #1301, and so on up
  to #1321.
- Linear's GitHub integration already moves issues to In Review on PR open and to Done on merge. It also marks
  an issue Done when its PR merges into a stack branch, so that issue reads Done before its code is on main.

## Decisions

| Area | Decision |
|---|---|
| Which PRs | PRs you authored, drafts included, in repos where tending is on. Drafts are never merged. |
| Pushing | Default is `always`. The setting `push = "until_approved"` holds fixes once a PR is approved, because a push cancels the approval. |
| Workspace | One worktree per PR, inside the clone Glidepath already keeps. Your dev checkout is never touched. Never force-pushes. If the remote moved, Glidepath rebases its own commit onto it; if that conflicts, it stops and asks you. |
| Cadence | A gh check every 5 minutes that uses no tokens, run by a second launchd job. Claude runs only when a PR's fingerprint changes: head commit, check results, new comments, reviews, mergeability, or main moving. |
| CI | If the failure looks like infrastructure or a flaky test, rerun it once. Otherwise fix it: never skip or delete tests, never weaken assertions or thresholds, never touch CI config. 2 tries per head commit. When a check can't run in the sandbox, fix from the logs, run whatever does run locally, and let CI confirm. |
| Comments | Acts on humans and review bots, not on your own comments. Bot nitpicks are fixed only when the fix is small. Every comment is judged: is it right, in scope, and worth doing? |
| Agreeing | Fix it, reply "Fixed in `abc1234`: what changed", and resolve the thread. |
| Disagreeing | Set by `disagree = "reply_resolve"` (yours) or `"draft"` (the default for new users, held in Needs you). |
| Commits | One commit per round, in the repo's own message style, with no attribution or marker. |
| Sandbox | Claude runs in Claude Code's sandbox: it writes only inside the worktree, can reach only package registries, and has no GitHub credentials. Glidepath checks the diff, then does the commit, push, reply and resolve itself. |
| Merge | Set by `merge = "auto" \| "ask" \| "off"`. The default for new users is `ask`. A PR is ready when it has the required approvals, the required checks are green, all threads are resolved, it has no conflicts, and it isn't a draft. |
| Merge method | Per repo, default `merge` (a merge commit). |
| Stacks | Bottom-up. Merge the bottom PR into main, then point the next PR at main. Because the merge is a merge commit, the next PR needs no rebase or push and keeps its approval. Repeat up the stack. |
| Conflicts | Merge main into the branch only when there is a real conflict. If the conflict is unclear, for example both sides changed the same logic, stop and ask you. |
| Hands off | A toggle on each PR row, the GitHub label `glidepath:hands-off` (anyone can add it), and the existing global Pause. Each takes effect at the next 5-minute check. |
| Limits | 5 rounds per PR per day and 2 tries per head commit. Tending shares the monthly token budget. When a limit is hit, the PR goes to Needs you. |
| Notifications | Only when it needs you: it's stuck, a limit was hit, a draft or held fix is waiting, a merge is waiting for your click, or main broke after a merge. Everything else goes silently into History. |
| Linear | Status changes stay with Linear's integration. Glidepath adds a comment when a PR is blocked. Merging stacks bottom-up already fixes the early Done. |
| UI | A new **Approach** section sits next to Now. Every tend round also shows up in History as a card. |
| Fix size | `max_fix_lines` is a setting. 400 is the default and 0 means no cap. |
| Autopilot | One toggle, which is Yazan's mode. It sets push `always`, disagree `reply_resolve` and merge `auto`. Where you would otherwise make the call, the **council** makes it. A revert PR is opened by itself, and a nudge pings by itself. Only the **hard stops** still come to you. |
| Hard stops | These reach you even on autopilot: a PushGuard refusal, a limit hit, a council that can't settle a question, a diff that touches the repo's `flag_paths`, a rebase that won't apply, and main broken after a revert. |
| Learning | Each repo has a **playbook**: verified commands plus lessons. Lessons come from what you teach it, from your edits to its drafts, from reviewers reopening threads or pushing back, from teammates reverting its commits, and from fixes that failed. Lessons apply straight away. You can see, edit and delete every one, and a weekly pass merges and trims them. |
| Advisor | Fix sessions run on Sonnet with `--advisor opus`, so Opus is consulted only at hard points. |
| Council | Three Sonnet judges with different lenses (correctness, reviewer intent, risk) vote independently. If all three agree, Glidepath acts. On a 2–1 split, an Opus chair decides. If the chair is unsure, the question goes to you. The council runs only when certain conditions are met, never by habit. |
| Usage guard | Each `claude -p` session emits `rate_limit_event` in stream-json, carrying the utilization (0–1) of the 5-hour or weekly window and when it resets. Glidepath records the latest values. Before starting work it checks that the work fits in what's left above the reserve. If it doesn't, the work waits until the window resets, and urgent work becomes a hard stop. API-key users get a dollar cap instead. |
| Separate account | Settings → "Claude account for Glidepath" can be set to a separate account. Glidepath gives it its own `CLAUDE_CONFIG_DIR` and signs it in with `claude auth login` in Terminal. Every session runs on that account, while your own `claude` stays on your main one. With a separate account the reserve defaults to 0%, and the usage guard watches that account's limits. The reserve is always a user setting (Settings → Tending, 0–90%), with or without a separate account. |
| Work classes | **Urgent** runs now: a PR that's approved or waiting to merge has red CI or a conflict. **Normal** runs now if it fits the reserve: other CI fixes and threads. **Deferred** runs in quiet hours: self-review, splits, lesson consolidation, the briefing, and backlog building. |
| Quiet hours | `quiet_hours`, default 22:00–07:00 plus weekends. This is the time your own Claude use is low, so deferred work uses window capacity you'd otherwise leave idle. Anthropic's own peak hours are not assumed: Glidepath goes by your hours and your windows. |
| Token economy | Checking costs no tokens. Internal output is terse (caveman style), and fixes are the smallest change that solves the root cause (ponytail style). Both are written into the skill text, so they don't depend on plugins. Evidence is trimmed in code. Each repo's verified commands are cached in its playbook. The skill text and playbook form a stable prefix, so the prompt cache hits. Each task gets the right model and effort. Every session has a `--max-budget-usd` cap. |

## Phases

Full build plan: `plan.md`. UI target: `prototype.html` (the Approach view).

### 1.6: Watch + CI

- `glidepath tend` runs the 5-minute check from launchd.
- Each PR has its state and fingerprint stored, plus its worktree.
- Fix sessions are sandboxed.
- A push guard runs before every push.
- Hands off and the limits above apply.
- A new **Approach** section shows your PRs as planes on approach to main. Settings gets a Tending section.


### 1.7: Comments

- Thread triage (agree / disagree / unclear) and fixes in the same round as CI.
- Replies and resolves.
- The `disagree` setting.
- After a round, re-request review from the reviewers whose threads were addressed.

### 1.8: Merge

- The readiness check and the `merge` setting.
- The merge method per repo.
- Bottom-up stack merging, with each next PR pointed at main.
- Merging main in on conflict.
- Deleting the branch after merge.
- Watching main's CI after a merge, with a revert PR offered if the merge broke main.

### 1.9: Extras

- **Self-review first:** Glidepath's own reviewer runs on your new PR, and its blockers are fixed before teammates
  see it.
- **Keep the PR description current:** after each round, update the summary and test plan.
- **Nudges:** when a PR has waited longer than N hours, tell you who it's waiting on.
- **Linear blocked comments.**
- **Daily digest:** once each morning, what merged, what's blocked and on whom, and what Glidepath fixed overnight.

### 1.10: Split big PRs

- When your PR goes over `split_over_lines`, Glidepath proposes a stack of smaller PRs. If you accept, it builds
  the stack: branches, PRs, and bases.

### Later: Night shift (2.x)

Glidepath builds things while you're away.

- **Input.** It picks up issues you label or assign: GitHub issues with the label `glidepath`, or Linear issues
  in a "Glidepath" status. It can also pick up bugs it finds itself, such as a flaky test seen 3 times, a lint
  backlog, or a dependency bump.
- **When.** Only in quiet hours, and only within the usage reserve.
- **How.**
  1. Plan, using the council for anything non-trivial.
  2. Build in a sandboxed worktree.
  3. Self-review.
  4. Open a draft PR.
- **Then** the draft PR is tended like any of your own PRs. You wake up to draft PRs that are already green.
- **Limits.** At most N PRs per night (default 2). It never merges its own Night-shift PRs: a human must
  approve and land them.

## Out of scope for now

- PRs from forks: the head branch lives in another repo.
- PRs where a teammate pushed commits to your branch. Tending goes on, but it never rewrites their commits.
- Working while the Mac is asleep. There is no server, so tending only runs while the Mac is awake, the same as
  reviews.
