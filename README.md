<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/wordmark-dark.png">
    <img src="assets/brand/wordmark-light.png" alt="Glidepath" width="360">
  </picture>
</p>

<p align="center"><strong>PRs reviewed before you're back.</strong><br>
A free, open-source Mac menu bar app that runs Claude Code reviews of your team's pull requests on a schedule,
checks every finding against the code, and lands one review per PR.</p>

<p align="center">
  <a href="https://github.com/yznki/glidepath/actions/workflows/ci.yml"><img src="https://github.com/yznki/glidepath/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/yznki/glidepath/releases/latest"><img src="https://img.shields.io/github/v/release/yznki/glidepath" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-black" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
</p>

```sh
brew install yznki/tap/glidepath
glidepath init
```

Homebrew builds it from source on your Mac (a few minutes, needs Xcode's Command Line Tools), so there is no
Gatekeeper prompt. `init` checks your tools, asks which repos to watch, and does a dry run. On a new setup, nothing is posted until
you hold to post.

If the build stops with "Your Xcode is too outdated" or "You have not agreed to the Xcode license": with Xcode
installed, update it to the version your macOS needs and run `sudo xcodebuild -license accept`. With only the
Command Line Tools, run `xcode-select --install`.

<p align="center">
  <img src="docs/media/hero.gif" alt="The Glidepath popover: a stack of glass cards, one per pull request, each showing the author and the verdict." width="400">
</p>

- **Gist at a glance.** Approved, changes or skipped, and who the PR is from. Click a card for the reason.
- **Checked, not guessed.** A second pass re-opens every quoted line and drops findings that don't match the code.
- **You stay in control.** New repos hold each review until you press and hold to post. Swipe to discard.
- **Runs on your schedule.** A 24-hour dial, weekdays or any days you pick, pause for an hour or until tomorrow.
- **Your rules.** A Markdown file per repo with what your team cares about.
- **Your plan, your Mac.** Uses the Claude Code you already have. No account, no server, no telemetry.

Glidepath is for Claude Code. OpenAI Codex support is tracked in [#1](https://github.com/yznki/glidepath/issues/1);
add a 👍 if you want it.

## Safe on public repos

- Claude may run only Glidepath's own commands, each bound to the current run.
- A strict filter rejects any other shell command.
- Reads and writes stay inside the repo checkout and the run's scratch folder.
- GitHub tokens never reach the model.
- Only collaborators' PRs are reviewed. New repos hold each review as a draft until you post it.

Tested against one adversarial PR; see the transcript in [docs/security-test.md](docs/security-test.md). The full
design is in [docs/security.md](docs/security.md).

## Questions

**Do I need an API key?** No. Glidepath runs the `claude` CLI you already use, on your Claude plan. An
`ANTHROPIC_API_KEY` in your environment is passed through if you prefer API billing.

**What leaves my Mac?** Only what Claude Code and `gh` already send: the PR diffs and code Claude reads go to
Anthropic, and the reviews you post go to GitHub. Glidepath itself talks only to github.com (and its API, to check for
updates). No analytics, no server. Set `check_updates = false` to turn the update check off.

**Does it post as me?** Yes, through your `gh` login. New repos hold every review for you to post. Existing configs keep the posting mode they already have. `posting =
"comment"` or `"review"` posts automatically.

**Does it use my Claude setup?** Yes. Reviews run with your user-level Claude Code settings, hooks and global `CLAUDE.md`, so they follow your style and tools. A repo's own `.claude` settings are never loaded, so a PR can't change how it is reviewed.

**Does it touch my working copy?** No. Each repo gets its own clone under `~/glidepath/clones/`, and Glidepath refuses to run in a folder it didn't create.

**Private repos?** Yes, anything your `gh` login can read.

**How much does it use?** See [What it costs](#what-it-costs). New setups start on Sonnet with five PRs a sweep.

**Linux or Windows?** No, it's a native Mac app. The `glidepath` CLI is macOS-only too (it uses launchd).

## Contents

- [Questions](#questions)
- [How a run works](#how-a-run-works)
- [What it costs](#what-it-costs)
- [The menu bar app](#the-menu-bar-app)
- [Tending your own PRs](#tending-your-own-prs)
- [Drafts](#drafts), [Dashboard](#dashboard), [Notifications](#notifications)
- [Config](#config)
- [Commands](#commands)
- [Your review rules](#your-review-rules)
- [Requirements](#requirements), [Install from source](#install-from-source), [Uninstall](#uninstall), [Limits](#limits), [Development](#development)
- [License](#license)

## How a run works

On each scheduled time, for each configured repo:

1. **Fetch and filter.** Updates a local checkout of the repo to its default branch. A checkout with local changes
   stops the run. Lists open PRs and skips your own PRs (unless `include_own = true`), drafts, bot authors, authors
   outside the allowed set, PRs you have already reviewed at the current head, and PRs over `max_changed_lines`.
   At most `max_prs_per_run` PRs are kept per repo. Each skip is recorded with its reason.
2. **Gather.** The `gatherer` agent (Haiku), one per PR, reads the diff and writes the PR's details and the blast
   radius: each caller of changed code outside the diff. It uses the GitNexus graph when it is on, and grep when not.
3. **Review.** The `reviewer` agent (Sonnet), one per PR, reviews the change against a written rubric. Over
   `split_over_lines`, the review is split into one reviewer per area. A UI reviewer also runs when the PR changes
   UI files.
4. **Check.** The `checker` agent (Sonnet), one per PR, re-opens every quoted line and drops any finding that does
   not match the code. It keeps verified blockers. If the checker changes the verdict or a finding, one more check
   runs on the fixed draft.
5. **Land.** One review per PR. A new repo starts with `posting = "draft"`: each review is held for you to post
   from the app or the CLI (see [Drafts](#drafts)). With `posting = "comment"`, the review is posted directly as a
   comment whose first line is the verdict. With `posting = "review"`, it is APPROVE or REQUEST_CHANGES instead.

Each run starts `claude -p` in the checkout with the `glidepath` skill. The skill gathers and reviews through the
steps above, and posts with `glidepath post`.

Glidepath is a single binary, `glidepath`. The scheduled job, the review skill and the menu bar app all come from that binary and the skill files it installs.

Results land in `~/.local/state/glidepath/runs/`. The menu bar app watches that folder and updates without polling.


## What it costs

Measured on a real team repo: 60 PRs reviewed across 16 sweeps (October 2026, with Opus running the main session). Tokens are input, output and cache
writes; cache reads are not counted.

| PR size (changed lines) | Median tokens per PR |
|---|---|
| under 300 | ~150k |
| 300 to 1,500 | ~240k |
| over 1,500 | ~500k |

The median over all PRs was ~340k, and a sweep took about 16 minutes. On a Pro plan that is a handful of PRs per
usage window, so start small: new setups review at most five PRs a sweep on Sonnet.

Glidepath uses three models, one per job:

- **The main session** (Sonnet for new setups, set with `model`) orchestrates the run and starts each step.
- **Haiku** gathers each PR: the diff, the existing comments, and the callers of changed code.
- **Sonnet** reviews each PR, and a second Sonnet pass checks each finding against the code.

The cost controls are `max_prs_per_run`, `max_changed_lines`, the schedule, and `monthly_tokens`, an optional monthly budget (off by default)
that pauses scheduled sweeps when reached; manual runs ignore it. Each run records its total tokens and each PR its own; the app shows
both live.

## The menu bar app

The app follows [docs/design.md](docs/design.md). The header is an approach profile: a glide slope with four stage
labels (gather, review, check, land) and a runway on the right, where landed PRs park as marks. During a run, each
PR is a dot on the slope at the stage it is in.

<p align="center">
  <img src="docs/shots/menubar.png" alt="The menu bar glyphs on a light and a dark bar: idle, running with 3, changes waiting with 2, paused, failed." width="560">
</p>

| Running | Idle, with changes |
| --- | --- |
| <img src="docs/shots/running-dark.png" alt="Running: three PRs on the slope, two landed as changes and one approved" width="300"> | <img src="docs/shots/idle-changes-dark.png" alt="Idle with changes: two PRs need changes" width="300"> |
| The sweep is in progress. Dots move down the slope; each row shows its stage and a four-dash meter. | The last sweep is done. Changes are listed first, with the review's reason. |
| **Paused** | **Failed** |
| <img src="docs/shots/paused-dark.png" alt="Paused: rows dimmed, Resume button" width="300"> | <img src="docs/shots/failed-dark.png" alt="Failed: red headline, a cross at the touchdown point, rows carried over from the earlier sweep" width="300"> |
| Scheduled sweeps are skipped until you resume. Rows and marks are dimmed. | The last sweep did not finish. Rows carried over from an earlier sweep show when they were decided. |

- Header: the headline counts the sweep ("3 in flight, 4 landed"), the second line says what needs you ("2 need changes"),
  and the third gives the time. Other headlines are "All clear", "Last sweep failed" and "Paused".
- Rows: changes first, then no result, in flight (latest stage first), approved, and skipped. Each row has the PR
  title (one line), `#number · author`, and the status on the right. Changes rows also show the review's reason on a
  third line.
- Footer: Run now (or Resume while paused, or Stop while running) on the left, and a menu on the right with Pause,
  Open log, Open dashboard, the last run's token count, Open at login and Quit. On a first run, Edit repos… opens the config file.
- The popover is at most 640 pt tall. Past that, the list scrolls.
- Held reviews are cards in a stack on the strip. Click a card to open it, hold **Post** to post it, or swipe it away to discard it.
- Menu bar: a glyph echoing the app icon, a striped disc with a slot cut into it. A dot moves along the slot while
  running (with the count of active PRs), a count when changes are waiting (cleared when you open the popover), faded
  stripes while paused, and a cross at the touchdown point for a failed run. A small dot at the top right means a newer
  release is out.
- Footer menu: when a newer release is out, its first item is "Update to 1.1.0…". "Check for updates…" checks now.
- Stop signals the running sweep's process group. Reviews already posted stay posted; the PRs not yet reviewed show
  "No result".

Pause writes a marker file, so scheduled runs skip until you resume. Manual runs still work.

The app is the same binary as the CLI. Launched with no arguments, or with `app`, it opens the menu bar. Only one copy
runs: a second start prints "Glidepath is already running in the menu bar" and exits. While the window is open, the app
also shows a Dock icon, with a Dock menu and a badge for reviews waiting for you.


## Window

The menu bar popover is the quick glance. The window (Overview, Reviews, Repos, Schedule, Settings) is for setup,
settings and the review history, and opens from the popover's "Open Glidepath". With no config file, it opens on
onboarding. The window sections are Now (the live sweep, with stages, tokens and hold to stop), Reviews, Repos,
Schedule (a 24-hour dial with presets) and Settings (with search and a live view of `config.toml`).

| Now | Reviews |
| --- | --- |
| ![Now](docs/shots/app/now-dark.png) | ![Reviews](docs/shots/app/reviews-dark.png) |

## Tending your own PRs

Off by default. Settings → Tending → "Tend my PRs", then switch on the repos. A second launchd job,
`dev.glidepath.tend`, checks your open PRs every 5 minutes with `gh` only; Claude runs only when a PR's checks changed.

- A failing check is rerun once when it looks like infrastructure, or fixed in a worktree inside Glidepath's clone. The
  session runs in Claude Code's sandbox: it writes only in that worktree, reaches only package registries, and has no
  GitHub credentials. Glidepath checks the diff (no test skips, no CI config, no secrets, size cap), then commits with
  your git identity and pushes. It never force-pushes.
- `push = "until_approved"` (the default) holds a fix on an approved PR, since a push dismisses the approval.
- Review threads, "changes requested" reviews and plain comments on your PRs are handled in the same round: an agreed
  fix gets a reply ("Fixed in `abc1234`: …") and the thread is resolved. A disagreement or an unclear ask becomes a
  "Your call" with a draft, unless `disagree = "reply_resolve"`. Replies mention no one but the commenter and link only
  to this PR's commits.
- Limits: `rounds_per_day` (5 per PR), `tries_per_head` (2), `max_usd_per_session` (2), and `usage_reserve` (40):
  Glidepath never spends the last 40% of your 5-hour and weekly Claude windows. Deferred work waits for
  `quiet_hours` ("22:00-07:00,sat,sun").
- Stop it per PR with the switch in its drawer or the `glidepath:hands-off` label, or everywhere with Pause.
- `glidepath teach owner/name "never edit migrations"` adds a lesson to the repo's playbook
  (`~/.config/glidepath/playbooks/`), which every session reads.

```toml
[tend]
enabled = true
push = "always"          # or "until_approved"
advisor = "opus"         # Sonnet fixes, Opus consulted at hard points; "off" to skip
disagree = "draft"       # or "reply_resolve"
usage_reserve = 40

[[repo]]
slug = "owner/name"
tend = true
```

## Drafts

With `posting = "draft"`, a sweep runs the whole pipeline and checks each review exactly as `comment` or `review`
would, but holds it instead of posting. A held review is a draft. Its row shows the verdict, with **Post** and
**Discard** at the right of the second line, and the header says how many wait ("3 drafts to post").

- **Post** asks first, with the verdict and the start of the review. It runs `glidepath drafts post`, which checks the
  stored review again, fetches the PR, and refuses if its head has moved since the review. A refused draft is marked
  stale, and the next sweep reviews the PR again. A post that works removes the draft.
- **Discard** deletes the draft. The row keeps its verdict.
- From a terminal: `glidepath drafts list`, `glidepath drafts post owner/name N` and `glidepath drafts discard owner/name N`
  act on the newest open draft for that PR. Review sessions cannot run these commands.

Drafts are kept under `~/.local/state/glidepath/drafts/`, one file per PR. A newer draft for a PR replaces the older one.

## Reviewing a large PR

A PR over `max_changed_lines` is skipped by sweeps and its row reads "Too large · 12,480 lines". Its **Review** action
(line 2, right) asks first, with the size, the limit and, when the last run allows it, a rough token estimate. It runs
`glidepath review owner/name N`, which reviews that PR alone and follows `posting` as usual.

## Reviewing by hand

Review one PR, or every open PR by one author, now. From a terminal:

```
glidepath review owner/name 1219
glidepath review owner/name 1219 1220 1225
glidepath review https://github.com/owner/name/pull/1219 https://github.com/other/repo/pull/7
glidepath review --author login [--repo owner/name]
```

Several PRs, from one repo or several, make one review run: one lock, and each PR is reviewed as if named alone.

The Now screen has the same thing: **Review a PR or author…** sits under **Run now**. For a PR, it takes PR numbers in the picked repo and GitHub PR links, separated by commas or spaces (`12, 15`), or lists the authors with open PRs in your repos (with a search box) and reviews all of one author's. The app asks first when the review would post for real.

A by-hand review ignores the `authors` list, `max_changed_lines`, `max_prs_per_run`, and the draft and bot skips. A named PR is reviewed even if it is yours. `--author` still skips your own PRs unless `include_own` is on. Both still skip PRs already reviewed at the current head, and PRs with a held draft at that head. `--again` reviews those two again, as it does for `review owner/name N`. `--dry-run` reviews and posts nothing. `posting` applies as usual.

## Dashboard

`glidepath dashboard`, or Open dashboard in the menu, writes one page to `~/.local/state/glidepath/dashboard/index.html`
and opens it in your browser. It shows the open drafts, with their full text and the command that posts each one, then
the last 50 runs: date, duration, tokens, and each PR's title, number (linked on GitHub), author, verdict and reason.
The page has no script. Every string from GitHub or the model is escaped, and it follows light and dark mode.

## Notifications

When a sweep finishes, Glidepath posts one notification: "Sweep done" with the counts ("2 need changes · 3 approved",
"All clear · 5 reviewed", or "3 drafts to post"), or "Sweep failed" with the run's error. A sweep with no PRs reviewed
says nothing, and a dry run never notifies. A one-PR review from `glidepath review` notifies only when it fails ("Review failed").
Clicking the notification opens the popover. The first launch after an
update asks for permission. If it is denied, the app logs that once and carries on.

Turn notifications off with `notify = false` in the config. The app has no menu item for this; the config is the
one place to change it. Three more keys: `notify_changes_only = true` skips the notification unless changes are waiting,
`notify_sound` picks the sound (`none`, `glass`, `pop`, `tink` or `hero`; default `glass`), and `respect_focus = false`
lets the notification break through a Focus mode.

## Config

`~/.config/glidepath/config.toml`:

```toml
schedule = ["08:00", "12:00", "16:00", "20:00"]   # global; one launchd job
check_updates = true          # false turns off the automatic check for new releases
notify = true                 # false turns off the notification when a sweep finishes
notify_changes_only = false   # true notifies only when changes are waiting
notify_sound = "glass"        # none | glass | pop | tink | hero
respect_focus = true          # false lets notifications break through Focus
model = "sonnet"              # haiku | sonnet | opus
strictness = "balanced"       # relaxed | easygoing | balanced | exacting | ruthless
review_drafts = false         # true also reviews draft PRs
include_bots = false          # true also reviews PRs opened by bots
monthly_tokens = 0            # monthly token budget; 0 is no budget
pause_at_budget = true        # pause scheduled runs once the budget is used
dry_run = false               # true reviews and posts nothing
hotkey = true                 # true is ⌥⌘G, false is off, or a shortcut such as "⌥⌘G"

[limits]
max_prs_per_run = 5
max_changed_lines = 3000      # bigger PRs are skipped with reason "too large"
split_over_lines = 1500       # reviews are split by area above this

[[repo]]
slug = "acme/api"
clone = "~/glidepath/clones/acme-api"   # init clones a dedicated detached checkout
posting = "draft"             # draft | comment | review
authors = "collaborators"     # collaborators | anyone | ["login", ...]
rules = "~/.config/glidepath/rules/acme-api.md"   # optional
rules_mode = "extend"         # extend | replace
gitnexus = "auto"             # auto | on | off
gitnexus_refresh = true       # re-index the clone before a sweep that reviews something (GitNexus on only)
include_own = false           # true to review your own PRs too
review_drafts = true          # optional: overrides the top-level review_drafts for this repo
flag_paths = ["infra/", ".github/workflows/"]   # optional: PRs touching these get a note
flag_note = "Needs a devops code-owner approval."  # optional: the note text
```

| Key | Default | Meaning |
| --- | --- | --- |
| `schedule` | `08:00`, `12:00`, `16:00`, `20:00` | Local times for scheduled runs. One launchd job for all repos. |
| `check_updates` | `true` | Check GitHub for a newer release at launch, daily and when the popover opens. `false` turns those checks off; "Check for updates…" still works. |
| `notify` | `true` | Notify when a sweep finishes. See [Notifications](#notifications). |
| `notify_changes_only` | `false` | Notify only when a sweep has changes waiting. |
| `notify_sound` | `glass` | `none`, `glass`, `pop`, `tink` or `hero`. |
| `respect_focus` | `true` | Notifications are held while a Focus mode is on. `false` lets them through. |
| `review_drafts` | `false` | Review draft PRs too. Draft PRs get normal verdicts. |
| `include_bots` | `false` | Review PRs opened by bots too. |
| `model` | `opus` when omitted; new setups write `sonnet` | Model for the review: `haiku`, `sonnet` or `opus`. New setups from onboarding and `init` start on Sonnet. |
| `strictness` | `balanced` | How much the review flags: `relaxed`, `easygoing`, `balanced`, `exacting` or `ruthless`. |
| `monthly_tokens` | `0` | Token budget for the calendar month. `0` is no budget. The Schedule page and Settings show the month's use against it. |
| `pause_at_budget` | `true` | Skip scheduled runs once the month's tokens reach `monthly_tokens`. Manual runs still work. |
| `dry_run` | `false` | Review everything and post nothing, as `glidepath run --dry-run` does. |
| `hotkey` | `true` | The global shortcut that opens the popover: `true` is ⌥⌘G, `false` turns it off, or a shortcut string such as `"⌥⌘G"`. |
| `limits.max_prs_per_run` | `10` when omitted; new setups write `5` | PRs per repo per run. Extra PRs are skipped with reason "over max_prs_per_run". New setups start with five per sweep. |
| `limits.max_changed_lines` | `3000` | Additions plus deletions above this are skipped with reason "too large". |
| `limits.split_over_lines` | `1500` | Above this, the review is split into one reviewer per area. |
| `repo.slug` | required | `owner/name` on GitHub. |
| `repo.clone` | `~/glidepath/clones/<owner>-<name>` | Detached checkout the skill reads. Never used for work. |
| `repo.posting` | `comment` when omitted; `draft` for new repos | `draft` holds the review until you post it; see [Drafts](#drafts). New repos, from `init`, onboarding and Repos, are written with `posting = "draft"`. `comment` posts directly as a COMMENT review whose first line is `Verdict: approve` or `Verdict: changes`. `review` posts APPROVE or REQUEST_CHANGES. |
| `repo.authors` | `collaborators` | `collaborators` means write, maintain or admin access on the repo. `anyone` means any author. A list means only those logins. |
| `repo.rules` | none | A Markdown file with extra review rules for this repo. |
| `repo.rules_mode` | `extend` | `extend` adds the file to the built-in rubric. `replace` swaps out the rubric's review bar. Safety and output sections always apply. |
| `repo.gitnexus` | `auto` | Use the GitNexus MCP tools for blast radius. `auto` uses them when the `gitnexus` command is on your PATH and `authors` is not `"anyone"`. Otherwise the skill uses grep. |
| `repo.gitnexus_refresh` | `true` | Before a sweep that reviews something, run `gitnexus analyze --index-only` in the clone (10-minute limit). If that fails or times out, GitNexus is off for this repo in this run. Has no effect when GitNexus is off. |
| `repo.review_drafts` | inherits | `true` or `false` overrides the top-level `review_drafts` for this repo. Leave it out to inherit. |
| `repo.include_own` | `false` | Review PRs you opened too. Off by default. GitHub accepts only a COMMENT review on your own PR, so `post` sends COMMENT for those whatever `posting` says. |
| `repo.flag_paths` | none | Path prefixes that need an extra approval. A PR whose changed files start with one gets a final line on its review: the note, and up to three matched paths. The verdict does not change, and the row shows "Flagged". |
| `repo.flag_note` | "Touches flagged paths; needs an extra approval." | The text of that note. Used only with `flag_paths`. |

Edits take effect on the next run. `glidepath doctor` checks the file.

### Testing without touching your config

`XDG_CONFIG_HOME` and `XDG_STATE_HOME` (absolute paths only) move Glidepath's own config and state folders, for
example for a sandboxed test run. HOME is not changed, so claude and gh keep their sign-in (the runner also pins gh's
config directory to `~/.config/gh`).


## Commands

| Command | What it does |
| --- | --- |
| `glidepath init` | Set up config, clones, skill, app link and schedule. Ends with a dry run. |
| `glidepath init --refresh` | Re-link the skill, app and schedule to the installed binary. No prompts, no dry run. `update` runs it after an upgrade. |
| `glidepath update` | Upgrade a Homebrew install to the latest release. See [Updating](#updating). |
| `glidepath run [--dry-run] [--repo owner/name]` | Run now. `--dry-run` reviews and posts nothing. |
| `glidepath state show [--run ID]` | Print a run as JSON. Defaults to the current run. |
| `glidepath pr info` / `pr diff` / `pr threads` / `post` | Used by the review session. Run them only inside a run; see [docs/security.md](docs/security.md). |
| `glidepath review owner/name N [N...] \| PR-URL [PR-URL...] \| --author login [--repo owner/name] [--dry-run] [--again]` | Review open PRs now (numbers or links, one or several), or every open PR by one author. By hand, the authors list, size limit, per-run cap and draft and bot skips do not apply. A named PR is reviewed even if it is yours. See [Reviewing by hand](#reviewing-by-hand). Refused while a run is in progress. |
| `glidepath drafts list` / `post owner/name N` / `discard owner/name N` | List, post or discard held reviews. See [Drafts](#drafts). |
| `glidepath dashboard` | Write the dashboard page and open it. See [Dashboard](#dashboard). |
| `glidepath pause` / `resume` | Skip or allow scheduled runs. |
| `glidepath doctor` | Check requirements and installed pieces. |
| `glidepath uninstall [--purge]` | Remove the schedule, skill and app link. `--purge` also removes config and state. |

`state set` (`--run`, `--repo`, `--pr`, `--stage gather|review|check`, `--reason`) and the `pr` and `post` commands are
used by the review session and refuse to run outside one.


## Your review rules

A repo can add a Markdown rules file with `rules`, and `rules_mode` chooses how it combines with the built-in rubric
(`extend` or `replace`). The rules file is read by the reviewer and may be quoted in public comments, so keep secrets,
tokens, internal hostnames and private data out of it.



## Requirements

- macOS 14 or later, Apple Silicon or Intel.
- Xcode Command Line Tools (`xcode-select --install`).
- `git`, from the Command Line Tools.
- `gh`, the GitHub CLI, signed in with the `repo` scope (`gh auth login`, or `gh auth refresh -s repo`).
- `claude`, Claude Code 2.1.306 or later, logged in. Install with `brew install --cask claude-code`.
- GitNexus is optional. See [Config](#config) for `gitnexus`.

`glidepath init` checks each of these and prints the fix command for any that is missing. Claude Code 2.1.306 or later
is needed because the session flags in [docs/security.md](docs/security.md) were checked against that version. A gh
token with the `repo` scope is needed for private repos.

## Install from source

```sh
git clone https://github.com/yznki/glidepath.git
cd glidepath
swift build -c release
./make-app.sh --no-build      # optional: builds build/Glidepath.app
.build/release/glidepath init
```

`swift build` needs only the Command Line Tools. `swift test` needs the full Xcode toolchain, because the Command Line
Tools do not include XCTest.

## init walkthrough

`glidepath init` does these steps in order and stops at the first failed requirement:

1. **Requirements.** Checks Command Line Tools, `git`, `gh`, `gh` sign-in and `claude`.
2. **Config.** If there is no config yet, asks for a repo as `owner/name` (or takes `--repo owner/name`)
   and writes `~/.config/glidepath/config.toml` with the defaults. An existing config is kept.
3. **Clone.** Clones each repo with `gh repo clone` into its `clone` path and detaches it at the default branch.
4. **Skill.** Copies `SKILL.md` and `rubric.md` to `~/.claude/skills/glidepath/`.
5. **App.** Links `Glidepath.app` into `~/Applications/`. Skipped if the app is not next to the binary.
6. **Schedule.** Writes `~/Library/LaunchAgents/dev.glidepath.run.plist` and loads it with
   `launchctl bootstrap`. The plist runs `glidepath run --scheduled` at each `schedule` time, with
   the `PATH` from the shell you ran `init` in, plus the folder of `gitnexus` when `init` finds it (on the PATH, in
   `~/Library/pnpm`, `~/.local/share/pnpm`, `~/.npm-global/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or npm's global
   bin). If you change tools later (for example, move `gh`), run `init` again. `init --refresh` keeps the job's PATH
   and adds the `gitnexus` folder if it is missing. `glidepath doctor` says whether `gitnexus` is found.
7. **Dry run.** Runs `glidepath run --dry-run` on the first repo. It reviews, prints the drafts,
   and posts nothing.

After the dry run, open the menu bar app and check the output. Posting starts at the next scheduled time.

## Updating

A newer release shows as a line above the footer, with a link to its notes, and as a dot on the menu bar glyph.
For a Homebrew install, "Update to 1.1.0…" in the footer menu (or `glidepath update`) runs `brew update` and
`brew upgrade yznki/tap/glidepath`, then refreshes the skill, app link and schedule. Homebrew rebuilds from source, so
expect about a minute. The menu bar app restarts itself when it is done. If a sweep is running, the update waits for it
to end. A source build is not updated in place: the update opens the release page instead.

Upgrading from 1.0.2: run `brew upgrade yznki/tap/glidepath`, then `glidepath init --refresh` once.

```sh
glidepath update              # checks now; upgrades a Homebrew install
glidepath update --wait       # same, but waits for a running sweep to end first
```

Automatic checks can be turned off with `check_updates = false` in the config.

## Uninstall

```sh
glidepath uninstall          # removes the schedule, skill and app link; keeps config and state
glidepath uninstall --purge  # also removes config and state
brew uninstall glidepath     # removes the binary and app
```

Clones under `~/glidepath/clones/` are not removed. Delete them yourself if you no longer need them.

## Limits

- macOS only. The menu bar app needs AppKit and SwiftUI.
- GitHub only. The CLI calls `gh` and the GitHub REST API.
- Per-PR token totals include only the subagents the skill starts for that PR. They are attributed by the PR number in
  each subagent's brief. Main-session tokens count toward the run total only.

## Development

```sh
swift build                                        # Command Line Tools are enough
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # XCTest needs Xcode
./make-app.sh                                      # release build and app bundle
```

The app has two render modes that need no UI. `glidepath --snapshot <dir>` draws the design states from fixtures to
PNG files, light and dark, plus the menu bar glyphs. `glidepath --hero-gif <path>` writes the hero animation as a
looping GIF, with injected time.

CI runs `swift build` and `swift test` on macOS.


## License

MIT. See [LICENSE](LICENSE).
