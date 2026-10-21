# review-radar

review-radar runs Claude Code on a schedule to review open pull requests in the GitHub repos you list.
It posts the reviews to GitHub and shows the run in a macOS menu bar app: one blip per PR on a radar,
one strip per PR with its stage and verdict.

![Popover during a run (placeholder until a live screenshot is taken)](docs/shots/running-dark.png)

It is a single binary, `review-radar`. The scheduled job, the review skill and the menu bar app all
come from that binary and the skill files it installs.

## What it does

On each scheduled time, for each configured repo:

1. Updates a local checkout of the repo to its default branch. A checkout with local changes stops the run.
2. Lists open PRs. It skips your own PRs, drafts, bot authors, authors outside the allowed set,
   PRs you have already reviewed at the current head, and PRs over the size limit. Each skip is
   recorded with its reason.
3. Starts `claude -p` in that checkout with the `review-radar` skill. The skill gathers each PR's
   diff, reviews it against a written rubric, checks the findings against the code, and posts
   the review.

Results land in `~/.local/state/review-radar/runs/`. The menu bar app watches that folder and updates
without polling.

## Requirements

- macOS 14 or later, Apple Silicon or Intel.
- Xcode Command Line Tools (`xcode-select --install`).
- `git`, from the Command Line Tools.
- `gh`, the GitHub CLI, signed in (`gh auth login`).
- `claude`, Claude Code, logged in. Install with `brew install --cask claude-code`.
- GitNexus is optional. See [Config](#config) for `gitnexus`.

`review-radar init` checks each of these and prints the fix command for any that is missing.

## Install

From Homebrew (once the tap is published):

```sh
brew install yznki/tap/review-radar
review-radar init
```

From source:

```sh
git clone https://github.com/yznki/review-radar.git
cd review-radar
swift build -c release
./make-app.sh --no-build      # optional: builds build/Review Radar.app
.build/release/review-radar init
```

`swift build` needs only the Command Line Tools. `swift test` needs the full Xcode toolchain, because
the Command Line Tools do not include XCTest.

## init walkthrough

`review-radar init` does these steps in order and stops at the first failed requirement:

1. **Requirements.** Checks Command Line Tools, `git`, `gh`, `gh` sign-in and `claude`.
2. **Config.** If there is no config yet, asks for a repo as `owner/name` (or takes `--repo owner/name`)
   and writes `~/.config/review-radar/config.toml` with the defaults. An existing config is kept.
3. **Clone.** Clones each repo with `gh repo clone` into its `clone` path and detaches it at the default branch.
4. **Skill.** Copies `SKILL.md` and `rubric.md` to `~/.claude/skills/review-radar/`.
5. **App.** Links `Review Radar.app` into `~/Applications/`. Skipped if the app is not next to the binary.
6. **Schedule.** Writes `~/Library/LaunchAgents/dev.reviewradar.run.plist` and loads it with
   `launchctl bootstrap`. The plist runs `review-radar run --scheduled` at each `schedule` time, with
   the `PATH` from the shell you ran `init` in. If you change tools later (for example, move `gh`),
   run `init` again.
7. **Dry run.** Runs `review-radar run --dry-run` on the first repo. It reviews, prints the drafts,
   and posts nothing.

After the dry run, open the menu bar app and check the output. Posting starts at the next scheduled time.

## Config

`~/.config/review-radar/config.toml`:

```toml
schedule = ["07:00", "13:00", "19:00"]   # global; one launchd job

[limits]
max_prs_per_run = 10
max_changed_lines = 3000      # bigger PRs are skipped with reason "too large"
split_over_lines = 1500       # reviews are split by area above this

[[repo]]
slug = "acme/api"
clone = "~/review-radar/clones/acme-api"   # init clones a dedicated detached checkout
posting = "comment"           # comment | review
authors = "collaborators"     # collaborators | anyone | ["login", ...]
rules = "~/.config/review-radar/rules/acme-api.md"   # optional
rules_mode = "extend"         # extend | replace
gitnexus = "auto"             # auto | on | off
```

| Key | Default | Meaning |
| --- | --- | --- |
| `schedule` | `07:00`, `13:00`, `19:00` | Local times for scheduled runs. One launchd job for all repos. |
| `limits.max_prs_per_run` | `10` | PRs per repo per run. Extra PRs are skipped with reason "over max_prs_per_run". |
| `limits.max_changed_lines` | `3000` | Additions plus deletions above this are skipped with reason "too large". |
| `limits.split_over_lines` | `1500` | Above this, the review is split into one reviewer per area. |
| `repo.slug` | required | `owner/name` on GitHub. |
| `repo.clone` | `~/review-radar/clones/<owner>-<name>` | Detached checkout the skill reads. Never used for work. |
| `repo.posting` | `comment` | `comment` posts a COMMENT review whose first line is `Verdict: approve` or `Verdict: changes`. `review` posts APPROVE or REQUEST_CHANGES. |
| `repo.authors` | `collaborators` | `collaborators` means write, maintain or admin access on the repo. `anyone` means any author. A list means only those logins. |
| `repo.rules` | none | A Markdown file with extra review rules for this repo. |
| `repo.rules_mode` | `extend` | `extend` adds the file to the built-in rubric. `replace` swaps out the rubric's review bar. Safety and output sections always apply. |
| `repo.gitnexus` | `auto` | Use the GitNexus MCP tools for blast radius. `auto` uses them when the `gitnexus` command is on your PATH. Otherwise the skill uses grep. |

Edits take effect on the next run. `review-radar doctor` checks the file.

## Security model

- **Tool allowlist, no bypass.** The run uses `--permission-mode dontAsk` with an explicit
  `--allowedTools` list. Anything not on the list is denied rather than prompted, because there is no
  one to answer a prompt. `bypassPermissions` is never used.

  The list, in Claude Code's rule syntax:

  ```
  Read, Grep, Glob, Agent
  Bash(git fetch:*)  Bash(git diff:*)  Bash(git show:*)  Bash(git log:*)
  Bash(gh pr view:*)  Bash(gh pr diff:*)  Bash(gh pr list:*)
  Bash(gh api repos/*/pulls/*/reviews:*)     # left out of dry runs
  Bash(review-radar state:*)
  Edit(<run scratch directory>/**)           # Write is covered by Edit rules
  Read(<rules file>)                         # only when rules is set
  mcp__gitnexus__*                           # only when GitNexus is enabled
  ```

  There is no general shell. `gh api` matches by prefix, so the rule allows any method on
  those paths; the skill only issues POST for the review payload.

- **Collaborators only, by default.** A PR author is reviewed only when they have write access
  or higher. Use `authors = "anyone"` only on repos where you accept reviews of outside contributions.

- **PR text is untrusted.** Titles, bodies, comments, diffs and file contents are data. The skill
  says so and ignores instructions inside them. This reduces the risk of prompt injection, but
  it is not a guarantee. A PR that persuades the model convincingly can still get a bad
  review posted, which is why `posting = "comment"` is the default and dry runs exist.

- **Local clones are read-only in practice.** The clone is detached and refreshed with `git fetch`
  and `git checkout --detach`. A dirty clone stops the run. Nothing is committed or pushed.

- **Posting is visible.** Reviews appear under your GitHub account. "Run now" in the app asks for
  confirmation when any repo uses `posting = "review"`.

- **Secrets stay out of the state.** The run file holds PR numbers, titles, authors, verdicts and
  token counts. It does not hold tokens or transcripts. Transcripts stay in Claude Code's own folder.

## Cost

- Each PR is one or more Claude sessions: a gather step, a review per PR (more for large PRs,
  split by area), and a checker. Costs grow with diff size and with how much of the repo the
  reviewer reads.
- The caps are the cost controls: `max_prs_per_run`, `max_changed_lines`, and the schedule
  itself. Lower them to bound a run.
- Each run records its total tokens, and each PR records the tokens of its own subagents. The
  menu bar app shows both. Tokens are input, output and cache writes; cache reads are not counted.
- Typical token use is not measured yet. Run the dry run on a repo you know, read the totals in the
  app, and set the caps from that.

## Menu bar app

- Radar: blips move inward as a PR advances through gather, review, check and post. Posted PRs sit at the centre.
- Strips: grouped by repo, with the stage rail, the verdict stamp, the author and the reason.
- Header: running state with the count done, or the next scheduled time when idle.
- Footer: Run now, Pause or Resume, Log, Open at login, Quit.
- Pause writes a marker file, so scheduled runs skip until you resume. Manual runs still work.

The app is the same binary as the CLI. Launched with no arguments, or with `app`, it opens the menu bar.

## Commands

| Command | What it does |
| --- | --- |
| `review-radar init` | Set up config, clones, skill, app link and schedule. Ends with a dry run. |
| `review-radar run [--dry-run] [--repo owner/name]` | Run now. `--dry-run` reviews and posts nothing. |
| `review-radar state show [--run ID]` | Print a run as JSON. Defaults to the current run. |
| `review-radar pause` / `resume` | Skip or allow scheduled runs. |
| `review-radar doctor` | Check requirements and installed pieces. |
| `review-radar uninstall [--purge]` | Remove the schedule, skill and app link. `--purge` also removes config and state. |

`state set` is used by the skill at each stage. You do not need to run it by hand.

## Uninstall

```sh
review-radar uninstall          # removes the schedule, skill and app link; keeps config and state
review-radar uninstall --purge  # also removes config and state
brew uninstall review-radar     # removes the binary and app
```

Clones under `~/review-radar/clones/` are not removed. Delete them yourself if you no longer need them.

## Limits

- macOS only. The menu bar app needs AppKit and SwiftUI.
- GitHub only. The CLI calls `gh` and the GitHub REST API.
- Per-PR token totals include only the subagents the skill starts for that PR. They are
  attributed by the PR number in each subagent's brief. Main-session tokens count toward the run total only.
- The tap and the v1.0.0 release tarball are not published yet. The formula's `sha256` is a placeholder.

## Development

```sh
swift build                                        # Command Line Tools are enough
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # XCTest needs Xcode
./make-app.sh                                      # release build and app bundle
```

CI runs `swift build` and `swift test` on macOS.

## License

MIT. See [LICENSE](LICENSE).
