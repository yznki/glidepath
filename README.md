# glidepath

glidepath runs Claude Code on a schedule to review open pull requests in the GitHub repos you list.
It posts the reviews to GitHub and shows the run in a macOS menu bar app: one blip per PR on a radar,
one strip per PR with its stage and verdict.

![Popover during a run (placeholder until a live screenshot is taken)](docs/shots/running-dark.png)

It is a single binary, `glidepath`. The scheduled job, the review skill and the menu bar app all
come from that binary and the skill files it installs.

## What it does

On each scheduled time, for each configured repo:

1. Updates a local checkout of the repo to its default branch. A checkout with local changes stops the run.
2. Lists open PRs. It skips your own PRs, drafts, bot authors, authors outside the allowed set,
   PRs you have already reviewed at the current head, and PRs over the size limit. Each skip is
   recorded with its reason.
3. Starts `claude -p` in that checkout with the `glidepath` skill. The skill gathers each PR's
   diff, reviews it against a written rubric, checks the findings against the code, and posts
   the review.

Results land in `~/.local/state/glidepath/runs/`. The menu bar app watches that folder and updates
without polling.

## Requirements

- macOS 14 or later, Apple Silicon or Intel.
- Xcode Command Line Tools (`xcode-select --install`).
- `git`, from the Command Line Tools.
- `gh`, the GitHub CLI, signed in with the `repo` scope (`gh auth login`, or `gh auth refresh -s repo`).
- `claude`, Claude Code 2.1.306 or later, logged in. Install with `brew install --cask claude-code`.
- GitNexus is optional. See [Config](#config) for `gitnexus`.

`glidepath init` checks each of these and prints the fix command for any that is missing.

## Testing without touching your config

`XDG_CONFIG_HOME` and `XDG_STATE_HOME` (absolute paths only) move glidepath's own config and state
folders, for example for a sandboxed test run. HOME is not changed, so claude and gh keep their sign-in
(the runner also pins gh's config directory to `~/.config/gh`).

## Install

From Homebrew (once the tap is published):

```sh
brew install yznki/tap/glidepath
glidepath init
```

From source:

```sh
git clone https://github.com/yznki/glidepath.git
cd glidepath
swift build -c release
./make-app.sh --no-build      # optional: builds build/Glidepath.app
.build/release/glidepath init
```

`swift build` needs only the Command Line Tools. `swift test` needs the full Xcode toolchain, because
the Command Line Tools do not include XCTest.

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
   the `PATH` from the shell you ran `init` in. If you change tools later (for example, move `gh`),
   run `init` again.
7. **Dry run.** Runs `glidepath run --dry-run` on the first repo. It reviews, prints the drafts,
   and posts nothing.

After the dry run, open the menu bar app and check the output. Posting starts at the next scheduled time.

## Config

`~/.config/glidepath/config.toml`:

```toml
schedule = ["07:00", "13:00", "19:00"]   # global; one launchd job

[limits]
max_prs_per_run = 10
max_changed_lines = 3000      # bigger PRs are skipped with reason "too large"
split_over_lines = 1500       # reviews are split by area above this

[[repo]]
slug = "acme/api"
clone = "~/glidepath/clones/acme-api"   # init clones a dedicated detached checkout
posting = "comment"           # comment | review
authors = "collaborators"     # collaborators | anyone | ["login", ...]
rules = "~/.config/glidepath/rules/acme-api.md"   # optional
rules_mode = "extend"         # extend | replace
gitnexus = "auto"             # auto | on | off
include_own = false           # true to review your own PRs too
```

| Key | Default | Meaning |
| --- | --- | --- |
| `schedule` | `07:00`, `13:00`, `19:00` | Local times for scheduled runs. One launchd job for all repos. |
| `limits.max_prs_per_run` | `10` | PRs per repo per run. Extra PRs are skipped with reason "over max_prs_per_run". |
| `limits.max_changed_lines` | `3000` | Additions plus deletions above this are skipped with reason "too large". |
| `limits.split_over_lines` | `1500` | Above this, the review is split into one reviewer per area. |
| `repo.slug` | required | `owner/name` on GitHub. |
| `repo.clone` | `~/glidepath/clones/<owner>-<name>` | Detached checkout the skill reads. Never used for work. |
| `repo.posting` | `comment` | `comment` posts a COMMENT review whose first line is `Verdict: approve` or `Verdict: changes`. `review` posts APPROVE or REQUEST_CHANGES. |
| `repo.authors` | `collaborators` | `collaborators` means write, maintain or admin access on the repo. `anyone` means any author. A list means only those logins. |
| `repo.rules` | none | A Markdown file with extra review rules for this repo. |
| `repo.rules_mode` | `extend` | `extend` adds the file to the built-in rubric. `replace` swaps out the rubric's review bar. Safety and output sections always apply. |
| `repo.gitnexus` | `auto` | Use the GitNexus MCP tools for blast radius. `auto` uses them when the `gitnexus` command is on your PATH and `authors` is not `"anyone"`. Otherwise the skill uses grep. |
| `repo.include_own` | `false` | Review PRs you opened too. Off by default. GitHub accepts only a COMMENT review on your own PR, so `post` sends COMMENT for those whatever `posting` says. |

Edits take effect on the next run. `glidepath doctor` checks the file.

## Security model

A review session can read the PR and post one review. It cannot run git, gh or other commands, and it
cannot read or write outside the directories it needs. The layers below are independent: each one
blocks something the others might miss.

**1. Allowlist.** The session runs with `--permission-mode dontAsk` and this allowlist. Anything else is
denied rather than asked about, because nobody is there to answer.

```
Read(//<clone>/**)                     the checkout of the default branch
Read(//<scratch>/**)                   this run's scratch directory
Edit(//<scratch>/**)                   writes only under scratch
Read(//<rules file>)                   only when rules is set
Agent(gatherer)  Agent(reviewer)  Agent(checker)
Bash(glidepath pr info:*)  Bash(glidepath pr diff:*)  Bash(glidepath pr threads:*)
Bash(glidepath state set:*)  Bash(glidepath post:*)
Bash(glidepath code grep:*)  Bash(glidepath code files:*)   read-only search of the checkout
mcp__gitnexus__detect_changes  ...impact  ...api_impact  ...context  ...query  ...route_map  ...shape_check
                                       only when GitNexus is on
```

There is no bare `Read`, `Grep` or `Glob`. A bare Grep allow rule reads any path on the machine, so search
goes through `glidepath code grep`, which only reads the checkout's tracked files. The skill is not a
file the session reads: its text is passed as the system prompt.

**2. Bash guard hook.** The session has a PreToolUse hook on `Bash` that runs `glidepath hook bash-guard`
for every command. It denies any command that does not start with `glidepath `, and any command that
contains `;`, `&`, `|`, `$`, a backtick, `>`, `<`, `(`, `)`, or a newline. The guard fails closed: if its
input cannot be read, it blocks.

**3. Disallowed tools.** `WebFetch`, `WebSearch`, `Skill`, and `Bash(ps:*)`, `Bash(du:*)`, `Bash(lsof:*)`,
`Bash(which:*)` are denied even if something else allowed them.

**4. Wrappers, not commands.** The glidepath subcommands the session may use:

| Command | What it does |
| --- | --- |
| `glidepath pr info --repo R --pr N` | Title, author, head SHA, files and body, as JSON. Records the head SHA. |
| `glidepath pr diff --repo R --pr N [--path F]` | The diff, or one file's part of it. `F` must be a file in the PR. |
| `glidepath pr threads --repo R --pr N` | Existing comments and reviews. Read-only. Also works in dry runs. |
| `glidepath post --repo R --pr N` | Posts `final.json` after validation. Dry runs print the payload instead. |
| `glidepath code grep --pattern TEXT` | Fixed-string search of the checkout's tracked files. Replaces the Grep tool, which cannot be scoped. |
| `glidepath code files` | The checkout's tracked file list. Replaces the Glob tool. |
| `glidepath state set ...` | Stage progress for this run only. Cannot set verdicts or the post stage. |

Each wrapper takes only the flags listed here and checks its arguments against the run it is bound to. The
binding is set in the child process environment by the runner, not by the model. A repo or PR outside the
run is refused with `unknown PR for this run`. A PR whose head has moved since `pr info` is refused and
recorded as skipped. The wrappers call gh with an argument list, never through a shell.

**5. Posting checks.** Before anything is posted, `post` refuses a review that contains an image (`![`,
`<img`), an iframe, or a link to any host other than github.com. It also enforces the length limits, at
most 5 comments, and that each comment is on a file in the PR.

**6. Subagents.** The three subagents (`gatherer` on Haiku, `reviewer` and `checker` on Sonnet) are defined
by the session itself, in dontAsk, with the same allowlist and the same hook. Their `tools` field cannot
limit Bash to specific commands, so for Bash the limits are the allowlist and the guard, which apply to
subagents too.

**7. Your own hooks.** `run` refuses to start when `~/.claude/settings.json`, `~/.claude/settings.local.json`
or any hooks file under `~/.claude/plugins` defines a `PreToolUse`, `PostToolUse` or `PermissionRequest`
hook, because those hooks would run inside review sessions. The message names the file. `SessionStart`,
`UserPromptSubmit` and `Stop` hooks are allowed. `doctor` reports the same. To run reviews, move the hooks
out of those files, or stop the plugin that provides them, then run again.

**8. Settings and MCP.** The session loads only the user's settings (`--setting-sources user`), never the
clone's `.claude/` folder, and only the MCP servers the session defines (`--strict-mcp-config`). The
session's own settings (its hook and its allowlist) come from the command line.

**Environment.** The session gets `PATH`, `HOME`, `USER`, `LANG`, `TMPDIR`, claude's own variables
(`ANTHROPIC_API_KEY`, `CLAUDE_CODE_*`) and the run binding. `GH_TOKEN` and `GITHUB_TOKEN` are never
passed. The wrappers use your own gh sign-in, as gh's configuration and keychain provide it.

**GitNexus.** GitNexus can read the repos it has indexed, and `auto` mode turns it off whenever the
authors are `anyone`, because those PRs come from strangers. Set `gitnexus = "on"` explicitly to override.
Only the seven read-only GitNexus tools listed above are allowed; the tools that rename, sync groups or
query across repos are not.

**Rules file.** The rules file is visible to the reviewer and may be quoted in public comments. Never put
secrets, tokens, internal hostnames or private data in it.

**Your own PRs.** Skipped unless `include_own = true`. When they are reviewed, the review is a COMMENT with the
verdict in its first line, because GitHub does not accept APPROVE or REQUEST_CHANGES on your own PR.

**Collaborators only, by default.** A PR author is reviewed only when they have write, maintain or admin
access, and that permission must be readable. Without push access, the permission cannot be read, and
those PRs are skipped with that reason. For those authors, or any others, list the logins in `authors`.

**PR text is untrusted.** Titles, bodies, comments, diffs and file contents are data. The skill says so,
and the wrappers label PR text as data in their output. This is defence in depth, not a guarantee: a
convincing PR can still get a poor review posted. That is why `posting = "comment"` is the default, and why
dry runs exist.

**Posting is visible.** Reviews appear under your GitHub account. "Run now" in the app asks for
confirmation when any repo uses `posting = "review"`.

**Local state.** The run file holds PR numbers, titles, authors, verdicts and token counts. It holds no
tokens, and the session transcript stays in Claude Code's own folder.

**Requirements.** Claude Code 2.1.306 or later (the flags above were checked against that version).
A gh token with the `repo` scope, for private repos.

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

The app follows `docs/design.md`. The radar is an instrument: one blip per PR, placed by its progress (queued on
the outer ring, one step inward per phase, landed at the centre). The arm sweeps only while a run is in progress,
and the blips breathe while idle. Reduced motion stops the arm, the breathing and the pings.

- Header: the headline says what needs you ("2 need changes", "All clear", "Last sweep failed", "Paused") and the
  sub-line gives the detail (landed count, next sweep, error).
- Rows: sorted by what needs you: changes first, then in progress, approved, skipped, dropped. Each row has the PR
  title, `#number · author · reason`, and in the right column a verdict stamp or the phase word, with a four-part rail.
- Footer: Run now (or Running…, or Resume while paused) on the left, and a menu on the right with Pause, Open log,
  Open at login and Quit.
- Menu bar: idle ring, a rotating arm while running (with the count of active PRs), an amber dot when changes are
  waiting (cleared when you open the popover), pause marks while paused, and a warning triangle for a failed or
  unscheduled run.

Pause writes a marker file, so scheduled runs skip until you resume. Manual runs still work.

The app is the same binary as the CLI. Launched with no arguments, or with `app`, it opens the menu bar.
`glidepath --snapshot <dir>` renders the design states from fixtures to PNG files.

## Commands

| Command | What it does |
| --- | --- |
| `glidepath init` | Set up config, clones, skill, app link and schedule. Ends with a dry run. |
| `glidepath run [--dry-run] [--repo owner/name]` | Run now. `--dry-run` reviews and posts nothing. |
| `glidepath state show [--run ID]` | Print a run as JSON. Defaults to the current run. |
| `glidepath pr info` / `pr diff` / `pr threads` / `post` | Used by the review session. Run them only inside a run; see [Security model](#security-model). |
| `glidepath pause` / `resume` | Skip or allow scheduled runs. |
| `glidepath doctor` | Check requirements and installed pieces. |
| `glidepath uninstall [--purge]` | Remove the schedule, skill and app link. `--purge` also removes config and state. |

`state set` and the `pr` and `post` commands are used by the review session and refuse to run outside one.

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
