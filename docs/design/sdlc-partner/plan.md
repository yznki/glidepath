# Plan: Glidepath as an SDLC partner (1.6 to 1.10)

Spec and decisions: `spec.md`. UI prototype: `prototype.html`, with five states: Approach, PR detail, Morning
briefing, Split, and Popover.

Nothing is built until this plan is groomed. Each phase ships as its own minor release, with the same release
process as 1.5.0.

## Rules (all phases)

- **Toolchain.** Must build with Command Line Tools: no `@State`, `@Observable` or `#Preview`. View state lives
  in `ObservableObject` models.
- **Defaults.**
  - Never change `Config.parse` defaults. New keys parse to the safe value.
  - The recommended values are written only by the setup writers: init, onboarding, and the Settings toggles.
- **Style.** Match the surrounding comment style and reuse what exists:
  - `Shell`, `RunLock`, `RunStore`, `Paths`, `Launchd` and `TokenBudget`;
  - `Claude.childEnvironment` and `BashGuard`;
  - the clone sync in `Run.swift`, the notifications, and `Gotham`, `HoldButton`, `RunCard` and `RunDigest`.
- **Who touches GitHub.** Glidepath itself does every GitHub write: push, reply, resolve, merge, retarget, label
  and delete. A Claude session never holds GitHub credentials.
- **Git.** Every GitHub network call uses HTTPS with the gh credential helper, the same as the release flow.
  Glidepath never force-pushes.
- **Work split.**
  - Main session (Opus): design, skill text, and the spike at the start of each phase.
  - Haiku: the build steps, one brief per step group, each verified before the next starts.
  - Sonnet: review at the end of each phase.

## The model: a PR on approach

Glidepath is named after the glide path, the slope a plane follows down to the runway. Your PRs are planes on
approach to `main`. Every PR passes three markers before it lands:

| Marker | Gate | Cleared when |
|---|---|---|
| Outer | CI | every required check passes |
| Middle | Review | no unresolved threads, approval given, no changes requested |
| Inner | Ready | no conflicts, not a draft, and `mergeStateStatus == CLEAN` |
| Runway | Land | merged into `main` |

Each PR has one **phase**, which is what the UI draws:

- **taxiing**: draft.
- **flying**: moving, with Glidepath working on it.
- **waiting**: waiting on someone else, for example a reviewer or CI that's still running.
- **holding**: needs you. It's stuck, or something is held or waiting for your call.
- **cleared**: ready to land.
- **landed**: merged.

This model lives in `Core/Approach.swift` as pure code: it is built from the GraphQL data plus the tend state.
Tests pin it, and every phase adds to it.

## UI: Approach

A new sidebar section, **Approach**, sits between Now and History. Its sidebar label reads "N in the air".

- **Approach chart.**
  - Each PR is drawn as a glyph on a glide-slope fan that converges on a runway labelled MAIN.
  - The x position is the furthest marker passed.
  - Stacks fly in trail on one lane, numbered in landing order.
  - Phases:
    - flying: white glyph, a pulsing ring, and a moving dashed trail;
    - holding: amber glyph circling a racetrack loop;
    - waiting: a steady, dimmer glyph whose label names who it's waiting on;
    - taxiing: faint;
    - landed: the glyph slides onto the runway, the runway lights flash, and the glyph fades.
  - A slow radar sweep runs across the chart.
  - Built with SwiftUI `Canvas` and `TimelineView`, which works with CLT.
  - Respects Reduce Motion: no sweep, rings or trails, and holding is shown as a static amber glyph.
- **Needs you.** Rows for these items:
  - Ready to land: "Hold to land".
  - Your call: Edit, Post reply.
  - Fix held: Discard, Hold to push.
  - Stuck: Open PR, Try again.
  - Revert offered: Open revert PR.
  - The same items also appear in Now's Needs you and in the popover.
- **Tower.** A live log in a monospaced font: each round's actions as one line each, with the time. Click a
  line to expand the diff and the replies.
- **PR detail drawer.** Opens when you click a glyph or a row. It shows:
  - the landing checklist: the 4 gates, each with its state and whose move it is;
  - today's rounds, with a summary, tokens, and the thread verdicts;
  - the hands-off toggle.
- **Morning briefing.** A large card at the top of Approach on the first open after the briefing time, until
  you dismiss it. It has three columns: Landed, Blocked (and on whom), and Glidepath did.
- **Split builder.** Shows the source PR, the proposed stack as numbered lanes, and file chips you can drag
  between parts. Buttons: Build stack, Keep as one.
- **Popover.** A mini approach chart, the needs-you strips, and "Next look in N min".
- **Menu bar icon.** It gets a small amber dot when something is holding.

Each phase builds the slice of the UI it needs. The prototype is the target.

## The brain: autopilot, playbook, advisor, council, token economy

These pieces cut across every phase. The table at the end of this section shows which phase brings each one.

### Autopilot

- One toggle, `autopilot = true|false`, which parses to false. It lives in the Approach header and in
  Settings → Tending.
- Turning it on sets:
  - `push = always`;
  - `disagree = reply_resolve`;
  - `merge = auto`;
  - automatic revert PRs;
  - automatic nudge pings (at most one per reviewer per day);
  - automatic splitting, but only before a PR has any review.
- Anything that would have been "your call" goes to the council instead (see below).
- **Hard stops** come to you whatever the setting:
  - a PushGuard refusal;
  - a limit hit;
  - a council that can't settle a question;
  - a diff that touches the repo's `flag_paths` (the existing setting);
  - a rebase or merge that won't apply cleanly;
  - main still broken after a revert.
- `Autopilot.swift` (pure, tested) maps a proposed action plus the settings to one of: do it, ask the council,
  or ask you. It is the only place that decides who acts.

### Playbook (learning)

Each repo gets a playbook file: `~/.config/glidepath/playbooks/<owner>-<name>.md`. It has two sections.

- **Commands.** Verify commands that ran green, with how long they took and how many times they've been
  verified. Glidepath records these from each session's `ran` list once CI agrees, so later sessions skip
  working out how to test.
- **Lessons.** One line each, with the source and the date. They come from:
  - **Teach:** a field in the drawer, plus the command `glidepath teach <repo> "<text>"`.
  - **Your edits:** when you edit a held draft or a reply before posting, the difference becomes a lesson
    candidate.
  - **Pushback:** a reviewer reopens a thread Glidepath resolved, or replies that it was wrong.
  - **Reverts:** a teammate reverts or rewrites one of Glidepath's commits.
  - **Failed fixes:** two failed tries at the same check give a "what didn't work" lesson.
- A Haiku "lesson writer" turns each signal into at most one line, or into nothing.
  - Lessons apply straight away and are listed in the drawer and in Settings → Playbook, where you can edit or
    delete them.
  - A weekly Haiku pass merges duplicates and drops lessons that haven't been confirmed in 60 days.
  - The playbook is capped at about 2k tokens.
- The playbook is placed into every session's system prompt, after the skill text. That stable prefix keeps
  the prompt cache warm.

### Model routing and the advisor

| Task | Model | Effort | Advisor |
|---|---|---|---|
| CI fix, comment fix, conflict merge | Sonnet | medium | Opus (`--advisor opus`) |
| Thread triage (agree / disagree / unclear) | Sonnet | low | Opus |
| Lesson writer, weekly consolidation, briefing text | Haiku | low | none |
| Council judges | Sonnet | medium | none (they must stay independent) |
| Council chair, split planning | Opus | high | none |

- The advisor model must be at least as strong as the executor. Claude Code 2.1.310 supports `--advisor` and
  `advisorModel`.
- The setting `advisor = "opus" | "off"` defaults to `opus` in the setup writers.
- Every session gets `--max-budget-usd`, from `tend.max_usd_per_session` (default 2). Hitting the cap is a
  hard stop.

### Council

- **When it runs** is decided by rules in code, never by habit:
  - Autopilot would act where the human mode would have asked you: a disagree or unclear thread, or a conflict
    where both sides changed the same lines.
  - A revert decision.
  - A split plan.
  - Any session that reports `confidence: low`.
- **How it runs.**
  - Glidepath starts three `claude -p` judges in parallel. Each sees the same evidence plus the playbook, and
    each has one lens:
    - **Correctness:** is the claim true in the code?
    - **Intent:** what does the reviewer or the team actually want? This judge reads the playbook lessons
      about people.
    - **Risk:** blast radius, using GitNexus impact when it's on.
  - Each judge writes `{vote, reason, confidence}`, tersely.
- **Outcome.**
  - All three agree: Glidepath acts.
  - A 2–1 split: an Opus chair reads all three and decides, or returns `unsure`.
  - `unsure`, or any judge reports a security concern: a hard stop, sent to you.
- **Cost control.** At most `council_per_day` councils (default 10). The judges get only the trimmed evidence.
  Their output stays internal and is never posted.
- **UI.** A council card in the drawer shows the three seats and the chair's line. The Tower logs it, for
  example "Council 2–1, chair: keep, reply".

### Token economy

- Checking costs nothing. Claude runs only when a fingerprint changes.
- **Style written into the skill:**
  - Internal output is terse: evidence notes, `result.json`, judge reasons, lessons.
  - Text posted to GitHub (replies, commits, PR descriptions) is normal prose in the repo's own style.
  - Fixes are the smallest change that solves the root cause: no refactors, no new dependencies, no drive-by
    changes. The PushGuard's size cap backs this up.
- **Evidence trimmed in code:** only the failing jobs, the last 300 lines of each log, and only the diff hunks
  near the error or thread.
- **Cached commands:** the playbook's commands mean no rediscovery.
- **Stable prefix:** skill text and playbook first, the round's evidence last.
- **History:** tokens are shown per round, per council and per day. The monthly budget covers tending too.

### Usage guard, work classes, quiet hours

- **Reading usage.**
  - Every `claude -p` session Glidepath starts runs with `--output-format stream-json`. Glidepath picks
    `rate_limit_event` out of the stream: the 5-hour and weekly `used_percentage` and `resets_at`.
  - The latest values go to `state/usage.json`. Reviews feed it too, so it stays current without spending
    anything extra.
  - Pure `Core/UsageGuard.swift` (tested) answers one question: `canSpend(class, estimate) → now | wait(until)
    | stop`.
- **Rules.**
  - Glidepath never spends past `100 - usage_reserve` in either window. `usage_reserve` defaults to 40 and is
    set per user.
  - The estimate is that task type's median token cost, taken from History.
  - When `usage.json` is older than its reset time, the window is assumed to be fresh.
  - With no subscription data (API key or gateway): if the gateway reports `spend_limit`, it is used. Otherwise
    the existing `monthly_tokens` budget plus `max_usd_per_session` apply.
- **Work classes.**
  - **Urgent:** red CI or a conflict on a PR that's approved or waiting to merge, and main broken after a
    merge. Runs now within the reserve. If it doesn't fit, it's a hard stop and you get a notification.
  - **Normal:** other CI fixes and threads. Runs now if it fits; otherwise it is queued until the window resets.
  - **Deferred:** self-review, splits, lesson consolidation, the briefing text, and later the Night shift. Runs
    only in `quiet_hours`, and only within the reserve.
- **Queue.** `state/tend/queue.json` holds the waiting work with its class and the earliest time it can run.
  The 5-minute check drains it. The Approach header shows "2 waiting for quiet hours" or "Paused for usage ·
  resets 18:40".
- **Config:** `usage_reserve = 40` and `quiet_hours = "22:00-07:00,sat,sun"`. Both are set in onboarding, with
  one plain question: "When do you usually not use Claude?"
- **Spike (1.6):** confirm that `rate_limit_event` appears in headless stream-json for Pro and Max, and what
  its fields are.

### Which phase brings what

| Phase | Brain pieces |
|---|---|
| 1.6 | The usage guard, work classes and queue, and quiet hours; the playbook with commands and Teach; the advisor; model routing; `--max-budget-usd`; the token-economy style in the skill; the autopilot toggle and `Autopilot.swift` (CI decisions only). |
| 1.7 | The council for threads; lessons from your edits and from pushback; autopilot over disagree. |
| 1.8 | The council for conflicts and reverts; automatic revert PRs; autopilot merge. |
| 1.9 | The weekly lesson consolidation; automatic nudge pings; Settings → Playbook. |
| 1.10 | The council for split plans; automatic splitting before any review. |

---

## 1.6: Watch + CI

### Spike (main session)

- Done: Claude Code 2.1.310's `sandbox` settings support everything the plan needs:
  - `network.allowedDomains`;
  - `filesystem.denyRead` and `filesystem.allowWrite`;
  - by default, writes are allowed only in the working directory and the temp directory.
- Still to confirm by hand:
  - the sandbox actually blocks `api.github.com` from a test session;
  - `denyRead` on `~/.config/gh` works;
  - `gh run rerun --failed` and `gh run view --log-failed` work on Sager's runs.

### Config

```toml
[tend]
enabled = false            # setup writers write true
push = "until_approved"    # "always" | "until_approved"
rounds_per_day = 5
tries_per_head = 2
max_fix_lines = 400        # 0 = no cap
autopilot = false
advisor = "off"            # setup writers write "opus"
max_usd_per_session = 2.0
council_per_day = 10       # used from 1.7
registries = ["registry.npmjs.org", "*.pypi.org", "files.pythonhosted.org"]   # sandbox network allowlist
```

Per repo: `tend = false` by default. Yazan's config gets `enabled = true`, `push = "always"` and Sager
`tend = true`, written through the Settings toggle.

### Watch: `glidepath tend`

- A launchd job, `dev.glidepath.tend`, runs `glidepath tend` with `StartInterval = 300`. It is installed only
  while tending is on.
- `tend.lock` stops two tend checks from running at once.
- A per-clone lock, `clone.lock`, guards every git command that changes the clone or its worktrees. Review runs
  take it too.
- The check is skipped when paused, over the token budget, or with tending off.
- One GraphQL query per repo lists your open PRs, with:
  - number, title, body, isDraft, labels, reviewDecision, mergeable and mergeStateStatus;
  - the head branch and commit, the base branch, and whether the head is a fork;
  - `statusCheckRollup`: each context with its name, conclusion, required flag, and run URL;
  - review threads: id, isResolved, and each comment's id, author, whether the author is a bot, and body;
  - reviews: author, state and id.
- 1.6 uses only the CI fields. The rest is fetched now so the state file is stable from 1.7 on.
- Skip fork PRs, PRs labelled `glidepath:hands-off`, and PRs switched off in the app.
- **Fingerprint (1.6)** = the head commit plus the sorted (check, conclusion) pairs.
- **State file**: `state/tend/<owner>-<name>-<n>.json`, holding:
  - `fingerprint`;
  - `roundsToday` and `roundsDate`;
  - `triesByHead` and `rerunsByHead`;
  - `held`: commit, worktree and summary;
  - `stuck`: the reason, or nothing;
  - `off`;
  - `phase` and `statusLine`, which the app reads.
- If the fingerprint is unchanged, the check spends nothing. If it changed and a required check failed, one round
  starts. Pending checks are left alone until they finish.
- After each check it writes `state/tend/approach.json`, a snapshot of every PR with its phase, marker, label
  and stack position. The app reads this one file.

### Round

Rounds run one at a time.

1. **Limits.** If the PR is over `rounds_per_day` or `tries_per_head`, mark it stuck and notify.
2. **Worktree.**
   - `state/tend/wt/<owner>-<name>-<n>`, made with `git worktree add` from the clone, then hard reset to
     `origin/<branch>`.
   - It is reused across rounds and removed when the PR closes or merges.
3. **Evidence.** Write `scratch/<round>/evidence.md` with:
   - the failing checks;
   - `gh run view --log-failed`, trimmed to its last 300 lines per job;
   - the PR title, the body, and the diff stat.
   - Everything in it is marked as untrusted data.
4. **Session.**
   - Run `claude -p` in the worktree with:
     - `--settings` set to sandbox on, `autoAllowBashIfSandboxed`, and `network.allowedDomains = registries`;
     - `filesystem.denyRead` covering `~/.config/gh`, `~/.ssh`, `~/.git-credentials` and `~/Library/Keychains`;
     - the existing PreToolUse hook settings style, `--setting-sources user`, `--strict-mcp-config`, and no MCP.
   - The skill `tend.md` is installed next to the review skill. Its CI section holds the rules from the spec.
   - The session writes `result.json`:
     `{action: fix|rerun|giveup, summary, commit_message, ran: [cmd]}`.
5. **Apply.**
   - **rerun**: allowed once per head commit, then `gh run rerun --failed <id>`.
   - **giveup**: mark the PR stuck with the summary, and notify.
   - **fix**: run the PushGuard, then commit with the user's git identity.
     - If `push == until_approved` and the PR is approved: hold the commit and notify.
     - Otherwise push `HEAD:<branch>`.
     - If the push is rejected: fetch, rebase the one commit, and push again. If the rebase conflicts, abort,
       mark the PR stuck, and notify.
6. **Record.**
   - Update the counters.
   - Write a `RunState` with `kind = "tend"` and `target = "pr:owner/name#n"`. The PR row carries the action,
     summary and tokens.
   - `RunDigest` titles: "Fixed CI on #1301", "Reran Unit Tests on #1301", "Stuck on #1301".
   - Append a line to `state/tend/tower.jsonl` for the Tower.

### PushGuard (`Core/PushGuard.swift`, pure and tested)

It refuses a change when:

- a path is under `.github/`, or is `*.env*`, `*.pem` or `*.key`;
- a test file is deleted;
- an added line contains `.skip(`, `xit(`, `xdescribe(`, `@pytest.mark.skip`, `t.Skip(` or `it.todo(`;
- the change is over `max_fix_lines` lines;
- the change is empty.

A refusal marks the PR stuck with the reason.

### App (1.6 slice)

- The Approach section, with:
  - the chart (taxiing, flying, waiting, holding, and lanes, but no landing yet);
  - Needs you (fix held, stuck);
  - the Tower;
  - the detail drawer (CI gate and rounds).
- The popover gets a mini chart and the needs-you strips.
- Now's Needs you includes tend items.
- **Settings → Tending:**
  - on/off, which installs or removes the launchd job;
  - the repos to tend;
  - "When a PR is approved": push anyway, or hold;
  - rounds per day.
- Notifications for stuck PRs, held fixes, and a hit limit.

### Verify

- Tests for PushGuard, fingerprint, limits, tend config parsing, and the Approach phase and marker mapping.
- The CLT build works, and the snapshots cover Approach (flying, holding, waiting), the drawer, and the popover.
- Live check on a throwaway PR in a scratch repo:
  - break a test: within 5 minutes Glidepath pushes a fix, and the PR goes green;
  - add the hands-off label: the next check does nothing.

---

## 1.7: Comments

- **Fingerprint** adds the unresolved thread ids and their latest comment ids, plus the review ids and their
  states.
- **Trigger.** A round runs when there's a new comment on an unresolved thread, a new "changes requested", or a
  failing check. CI and threads are handled in one round, and make one commit.
- **Which comments count.**
  - Inline review threads.
  - Review bodies with "changes requested".
  - Plain PR comments that ask for a change, decided by the session.
  - Ignored: your own comments, threads where the last word is yours, and comments that only say "LGTM" or
    give an approval.
  - Bots are spotted by `[bot]` in the login, plus a list: coderabbitai, copilot-pull-request-reviewer, and a
    teammate's Glidepath, recognised by its review marker.
- **Evidence** adds `threads.md`: each thread's file, line, the code around it, and every comment, marked as
  untrusted.
- **Session** output adds `threads: [{id, verdict: agree|disagree|unclear, reply, fixed}]`, with these rules:
  - agree only if the comment is right and in scope;
  - for a bot nitpick, agree only when the fix is under 10 lines;
  - disagree means a concrete reason fits in the reply;
  - anything unclear goes to unclear.
- **Apply**, after the push:
  - **agree + fixed**: reply "Fixed in `abc1234`: <what changed>", then resolve with GraphQL
    `resolveReviewThread`.
  - **disagree**: depends on `disagree`:
    - `reply_resolve`: post the reply, then resolve.
    - `draft` (the default for new users): a "Your call" item in Needs you with the draft, and Edit, Post reply,
      Discard.
  - **unclear**: a "Your call" item with no draft.
  - A plain PR comment gets a reply only; there's no thread to resolve.
- **Reply guard (pure, tested).** At most 600 characters. No `@mentions` except the comment's own author. No
  links except to commits on this PR.
- **Re-request review.** After a round that addressed someone's "changes requested", re-request that
  reviewer's review via the requested_reviewers API, at most once per reviewer per round.
- **Config:** `disagree = "draft" | "reply_resolve"` parses to `draft`. Yazan's config gets `reply_resolve`.
- **UI:**
  - the drawer's thread gate and thread verdicts;
  - Your call rows;
  - Tower lines such as "replied to 2 threads, resolved 2".
- **Verify:**
  - tests for the reply guard, bot detection and the thread fingerprint;
  - live: a teammate comment gets fixed, replied to and resolved; a wrong comment gets the disagree path.

---

## 1.8: Merge

- **Fingerprint** adds the base branch, mergeStateStatus, reviewDecision, and main's head commit.
- **Readiness:** `mergeStateStatus == CLEAN`, `reviewDecision == APPROVED`, no unresolved threads, and not a
  draft. GitHub works out `CLEAN` from the repo's rulesets, so Glidepath doesn't re-implement them.
- **Merge setting:** `merge = "off" | "ask" | "auto"` parses to `off`; setup writes `ask`.
  - `ask`: Needs you shows "Ready to land" with Hold to land.
  - `auto`: Glidepath merges at the next check.
  - Merging runs `gh pr merge <n> --<method>`. The method is set per repo, `merge_method`, default `merge`.
- **Stacks.** Built from base refs among your open PRs. A PR whose base is another of your open PR's branches is
  that PR's child.
  - Only a PR whose base is the default branch can land.
  - After it merges, every child is retargeted to the default branch with `gh pr edit --base`, then the merged
    branch is deleted, in that order.
  - Landing order is shown on the chart.
  - The spike checks whether retargeting dismisses approvals under Sager's rulesets. If it does, the child shows
    "needs re-approval" and that becomes a Blocked item.
- **Independent PRs:** if several are ready in one check, land the oldest first, then re-read before landing
  the next, since main moved.
- **Conflicts** (`mergeStateStatus == DIRTY`):
  - A round runs `git merge origin/<default>` in the worktree.
  - On conflict, the session resolves it under the rule "if both sides changed the same logic, give up as
    unclear".
  - Then the PushGuard, and the push follows the push setting.
  - Never rebase.
- **Branch cleanup:** delete the head branch after the merge and after any retargets, and remove the worktree.
- **After a merge:**
  - Glidepath watches main's checks on the merge commit for up to 60 minutes.
  - If a required check fails on the merge commit and passed on its first parent, it notifies "main broke after
    #n" and adds "Open revert PR" to Needs you.
  - That button runs `git revert -m 1 <sha>` in a fresh worktree, pushes `revert-<n>`, and opens the PR.
  - It never runs on its own.
- **UI:**
  - the landing animation;
  - the runway lights;
  - stack lanes with landing numbers;
  - Ready to land and Revert rows;
  - the inner marker in the drawer.
- **Verify:**
  - tests for readiness, stack building, and landing order;
  - live: a 2-PR stack in a scratch repo lands bottom-up, and the child is retargeted with its approval kept.

---

## 1.9: Extras

- **Self-review first.**
  - Runs when one of your PRs appears or goes from draft to ready.
  - It runs the existing review pipeline on that PR in `self` mode: nothing is posted, and the findings are
    written to the tend scratch folder.
  - Verified blockers go into the next tend round, as if they were agreed threads but with no reply.
  - Once per PR per ready transition.
  - Config `self_review = true|false` parses to false; setup writes true.
- **PR description upkeep.**
  - After each round that pushes, rewrite only the text between `<!-- glidepath -->` and
    `<!-- /glidepath -->` in the PR body.
  - That block holds "Changes since review" (one line per round) and, when present, a test-plan checklist.
  - If the markers are missing, the block is appended. Nothing outside the markers is ever edited.
- **Nudges.**
  - When a PR has waited on a reviewer for more than `nudge_hours` (default 24, counting only weekday hours),
    it becomes a Blocked item: "Waiting 26 h on Gadi".
  - A Ping button posts a short, polite comment mentioning that reviewer. Only on your click.
- **Linear blocked comments.**
  - The Linear personal API key is kept in the Keychain and set in Settings.
  - The issue id comes from the title or branch (`[A-Z]+-\d+`).
  - When a PR becomes stuck, or waits longer than `nudge_hours`, Glidepath adds one comment to the issue per
    blocking reason. Status changes are left to Linear.
- **Daily digest.**
  - At `briefing_time` (default 08:00) on schedule days: a notification, plus the briefing card.
  - Built from the tend RunStates and `tower.jsonl` since the last briefing: Landed, Blocked (with whom),
    Glidepath did (rounds, threads, tokens).
- **UI:** the briefing card, Blocked rows with Ping, the self-review line on taxiing PRs, and Linear in Settings.
- **Verify:** tests for nudge hours, the description-marker rewrite, the Linear id parser, and the briefing
  composer.

---

## 1.10: Split big PRs

- **Trigger:** one of your PRs goes over `split_over_lines`, or you click "Split…" in the drawer.
- **Plan session** (sandboxed, read-only):
  - It reads the diff and proposes 2 to 6 ordered parts, as `split.json`:
    `[{title, why, files: [...], depends_on}]`.
  - Each part should build on its own.
  - v1 is split by file only; splitting inside a file comes later if needed.
- **Split builder UI:** drag file chips between parts, rename parts, then Build stack or Keep as one.
- **Build**, after you click:
  - For each part, in order, create the branch `<branch>-part-k` from the previous part (part 1 from the
    default branch) and check out only that part's files from the source branch.
  - Run the repo's typecheck and unit tests in the sandbox. If a part fails, stop and show which one.
  - Push, then open PRs with bases chained, and with the titles, why, and a stack table in each body.
  - The source PR becomes a draft, with a comment linking the stack. It is never closed automatically.
- **Then** the stack is tended and landed like any other stack.
- **Verify:** tests for split.json validation and the order of the branch plan; live: split a 3-part PR in a
  scratch repo.

---

## Later: Night shift (2.x)

See `spec.md`. It reuses the pieces built here: the worktree, the sandbox, the council, the usage guard with
the deferred class, self-review, and tending. The only new part is choosing which issue to take and planning it.

## Open items to confirm in the spikes

1. Whether retargeting a PR's base dismisses approvals under Sager's rulesets (1.8).
2. Whether `gh` can rerun a single failed job for Sager's runners (1.6).
3. Whether the sandbox blocks gh and git from reaching GitHub in practice, and not just on paper (1.6).
4. Whether `rate_limit_event` appears in headless stream-json for Pro and Max, and what its fields are (1.6).
