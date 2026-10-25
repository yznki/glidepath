# Changelog

## 1.8.0

- Landing: with `merge = "ask"` (what Settings writes when you turn tending on) a PR that is approved, green, clean and has no open threads shows "Ready to land" with Hold to land. `merge = "auto"` or autopilot lands it on the next check. The merge method is set per repo with `merge_method`.
- Stacks land bottom-up: after a PR merges, the PRs stacked on it are retargeted to main, then its branch is deleted (kept while any other open PR still uses it).
- Conflicts with main: Glidepath merges main into the branch (never rebases). A sandboxed session resolves conflicts; it gives up when both sides changed the same logic.
- After a merge Glidepath watches main for an hour. If a check fails on the merge commit that passed before it, you get "Main broke after #n" and an Open revert PR button. With autopilot, a council decides whether to open it.
- The Approach chart shows the landing, the landed plane on the runway, and the markers each PR has passed.

## 1.7.0

- Review comments: tending now reads review threads, "changes requested" reviews and plain comments on your PRs. Glidepath fixes what it agrees with in the same commit as any CI fix, replies "Fixed in `abc1234`: …", resolves the thread, and asks the reviewer to look again.
- When it disagrees or isn't sure, you get a "Your call" item with its draft reply: Edit, Post reply or Discard. Settings → Tending → "When Glidepath disagrees" can post and resolve instead.
- Every reply passes a guard: at most 600 characters, no @mentions except the commenter, no links except this PR's commits.
- With autopilot on, those calls go to a council first: three Sonnet judges (correctness, intent, risk) and an Opus chair on a split. Capped per day; a security concern or an unsure chair stops and asks you.
- Glidepath learns from your edits to its drafts and from reviewers who reopen a thread it resolved. Reviewer pushback is kept apart in the playbook and never treated as an instruction.
- Reviews Glidepath posts carry a hidden marker, so a teammate's Glidepath treats them like a bot's. Bot summary comments never start a round.

## 1.6.0

- Tending: Glidepath can look after your own PRs. Turn it on in Settings → Tending and pick the repos. Every 5 minutes it checks your open PRs for free; Claude runs only when something changed.
- When CI fails it reruns flaky jobs once or fixes the code in a sandboxed worktree (only package registries reachable, no GitHub credentials), checks the change, then commits and pushes it itself. It never skips tests, touches CI config or force-pushes.
- A new Approach section shows your PRs as planes on approach to main, a Tower log of what Glidepath did, and a drawer per PR with its gates, today's rounds and what Glidepath learned about the repo.
- Needs you: held fixes (Hold to push, Discard) and stuck PRs (Open PR, Try again), also in Now and the popover. The menu bar icon gets an amber dot.
- Limits: 5 rounds per PR a day, 2 tries per commit, a dollar cap per session, and a usage reserve: Glidepath never spends the last 40% of your 5-hour and weekly Claude windows. Heavy work waits for quiet hours.
- Optional separate Claude account for Glidepath, autopilot toggle, `glidepath:hands-off` label, per-PR switch, and `glidepath teach owner/name "lesson"`.

## 1.5.0

- Now shows what needs you and what each run did, in one sentence per run.
- Skipped PRs fold away.
- Reviews is now History.
- The popover shows only what needs you.

## 1.4.0

- The review sheet is a flight recorder: the PR's approach through its run (gather, review, check, land), its verdict, and readouts for the checker's changes, blast radius and the session's notes.
- A review the run left without a verdict, or a PR it skipped, has a Review again button; the sheet shows the notes the run left on what stopped it.
- The Tools check now finds Homebrew tools when the app is opened from Finder.
- "Fix all in Terminal" runs every missing fix.

## 1.3.8

- A review session waits for its agents before it ends, so their reviews are no longer dropped when the session finishes early.
- A PR the session left without a verdict shows as No result, and its row opens its review. Now rows open their review once the run has finished.

## 1.3.7

- Huge PRs (over GitHub's 300-file diff limit) are reviewed: when `gh pr diff` fails, the diff is built from the run's clone, `--path` included.
- GitNexus tools reach the gatherer subagents, so blast radius is read from the graph when GitNexus is on.
- A PR the session leaves without a verdict says why in its row ("review session ended without a verdict; see the log"). A PR the session skips with `state set --verdict skipped --reason` shows as Skipped with the session's reason.
- The GitNexus index refresh prints a short summary on success, not its whole log.

## 1.3.6

- `glidepath review` and the Review sheet take several PRs at once (`owner/name 12 15`, several PR links, or PRs from several repos), run as one review.

## 1.3.5

- `glidepath review` takes a PR link, and `--author login [--repo owner/name]` reviews every open PR by one author. A by-hand review ignores the authors list, size limit, per-run cap and draft and bot skips. A named PR is reviewed even if it is yours; `--author` still skips your own PRs unless `include_own` is on.
- Now has a "Review a PR or author…" link under Run now.

## 1.3.4

- `glidepath review owner/name N` on your own PR says how to turn on `include_own`, once the run's summary is printed.
- A review session reads the rubric from its scratch folder (with the repo's rules appended), so reviewers no longer fail to open it.
- `glidepath code files` refuses any flag with a plain message; the gatherer prompt says so.
- `glidepath init` suggests the repo of the current folder, asks again on a bad answer (three tries), and exits with the owner/name example.
- A run that reviews nothing says so ("no open PRs to review" or "0 PRs reviewed") before the token count.
- `glidepath init` ends by saying where reviews go for your posting mode.
- The allowlist and disallowed lines print only when output is not a terminal, so the scheduled log keeps them.
- Install notes for Xcode's license and version, in the README and the Homebrew caveats.
- `glidepath init` and `doctor` tell you to run `claude update` (or `brew upgrade --cask claude-code`) when Claude Code is too old.

## 1.3.3

- New setups hold each review for you to post, and start on Sonnet with five PRs a sweep. Existing configs are unchanged.
- Schedule's monthly token estimate comes from your real sweeps; it shows "—" until three have finished.
- Setup uses the 24-hour schedule dial; new setups default to weekdays 08:00–20:00, every 4 hours.
- Issue templates, a security policy and a contributing guide.
- Launch site.
- Glidepath only runs git in clones it created; a `clone` set to your own checkout is refused, and `glidepath doctor` says so.

## 1.3.2

- Popover: at most six cards, the rest behind a "+N more" strip that opens Reviews; the open card grows to fit; full header labels; solid dark frame.
- Setup screens in the Gotham look.
- Config keys this version doesn't know are kept instead of reopening setup; `glidepath doctor` lists them.
- Smoother Now page during a sweep.
- PRs over the per-run cap read "next sweep" instead of the config key.

## 1.3.1

Fixes the build on macOS 15 and older SDKs (menu commands over the builder limit).

## 1.3.0

**New look**
- Dark glass popover: held reviews are a card stack. Hold to post, swipe a card away to discard it.
- Now page: the live sweep with its stages and tokens. Hold to stop. Replaces Overview.
- Reviews grid, and a 24-hour Schedule dial with presets.
- Settings rebuilt, with search and a live view of `config.toml`.
- Dock icon while the window is open, with a Dock menu and a badge for waiting reviews.

**Reviewing**
- Review draft PRs, globally or per repo. Review bot PRs. Choose the model and strictness.
- Monthly token budget, with an option to pause scheduled runs once it is used.
- Notifications: pick a sound, notify only when changes are waiting, and respect Focus.
- Custom global shortcut. Timed pause. Menu bar icon styles. Signal colour, glass and motion settings.

**New config keys**
- `review_drafts` (also per `[[repo]]`), `include_bots`, `model`, `strictness`, `notify_changes_only`,
  `notify_sound`, `respect_focus`, `monthly_tokens`, `pause_at_budget`, `dry_run`, and `hotkey` (a bool or a shortcut such as `"⌥⌘G"`).
