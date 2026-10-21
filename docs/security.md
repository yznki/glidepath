# Security model

The short version is in the [README](../README.md#safe-on-public-repos). This page is the detail. The adversarial test is in [security-test.md](security-test.md).

The layers below are independent. Each one blocks something the others might miss.

## Design, in five points

- Claude may only run Glidepath's own subcommands, and each one is bound to the current run.
- A byte-level guard rejects any other shell command.
- Reads and writes are scoped to the checkout and the run's scratch folder.
- GitHub tokens never reach the model.
- Reviews are for collaborators' PRs only, and comment-only, by default.

## Details

## Allowlist

The session runs with `--permission-mode dontAsk` and this allowlist. Anything else is denied rather than asked
about, because nobody is there to answer.

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

There is no bare `Read`, `Grep` or `Glob`. A bare Grep allow rule reads any path on the machine, so search goes
through `glidepath code grep`, which only reads the checkout's tracked files. The skill is not a file the session
reads: its text is passed as the system prompt.

## Bash guard hook

The session has a PreToolUse hook on `Bash` that runs `glidepath hook bash-guard` for every command. The command must
be `glidepath ` followed by plain words (letters, digits and `_./:,@+-`) and single-quoted strings. Anything else is
denied, including `;`, `&`, `|`, `$`, backticks, `<`, `>`, redirects, braces, globs, `~`, `!`, `#`, backslashes,
`=(...)` and zsh glob qualifiers. Parentheses inside a quoted string are fine. An unquoted value that starts with
`--` is denied, so a flag cannot be passed as a value. The guard fails closed: if its input cannot be read, it blocks.

## Disallowed tools

`WebFetch`, `WebSearch`, `Skill`, and `Bash(ps:*)`, `Bash(du:*)`, `Bash(lsof:*)`, `Bash(which:*)` are denied even if
something else allowed them.

## Wrappers

The Glidepath subcommands the session may use:

| Command | What it does |
| --- | --- |
| `glidepath pr info --repo R --pr N` | Title, author, head SHA, files and body, as JSON. Records the head SHA. |
| `glidepath pr diff --repo R --pr N [--path F]` | The diff, or one file's part of it. `F` must be a file in the PR. |
| `glidepath pr threads --repo R --pr N` | Existing comments and reviews. Read-only. Also works in dry runs. |
| `glidepath post --repo R --pr N` | Posts `final.json` after validation. Dry runs print the payload instead. |
| `glidepath code grep --pattern TEXT` | Fixed-string search of the checkout's tracked files. Replaces the Grep tool, which cannot be scoped. |
| `glidepath code files` | The checkout's tracked file list. Replaces the Glob tool. |
| `glidepath state set ...` | Stage progress for this run only. Cannot set verdicts or the post stage. |

Each wrapper takes only the flags listed here and checks its arguments against the run it is bound to. The binding
is set in the child process environment by the runner, not by the model. A repo or PR outside the run is refused
with `unknown PR for this run`. A PR whose head has moved since `pr info` is refused and recorded as skipped. The
wrappers call gh with an argument list, never through a shell.

## Posting checks

Before anything is posted, `post` refuses a review that contains an image (`![`, `<img`), an iframe, or a link to
any host other than github.com. It also enforces the length limits, at most 5 comments, and that each comment is on
a file in the PR.

## Subagents

The three subagents (`gatherer` on Haiku, `reviewer` and `checker` on Sonnet) are defined by the session itself, in
dontAsk, with the same allowlist and the same hook. Their `tools` field cannot limit Bash to specific commands, so
for Bash the limits are the allowlist and the guard, which apply to subagents too.

## Your own hooks

`run` refuses to start when `~/.claude/settings.json`, `~/.claude/settings.local.json` or any hooks file under
`~/.claude/plugins` defines a `PreToolUse`, `PostToolUse` or `PermissionRequest` hook, because those hooks would run
inside review sessions. The message names the file. `SessionStart`, `UserPromptSubmit` and `Stop` hooks are allowed.
`doctor` reports the same. To run reviews, move the hooks out of those files, or stop the plugin that provides them,
then run again.

## Settings and MCP

The session loads only the user's settings (`--setting-sources user`), never the clone's `.claude/` folder, and only
the MCP servers the session defines (`--strict-mcp-config`). The session's own settings (its hook and its allowlist)
come from the command line.

## Environment

The session gets `PATH`, `HOME`, `USER`, `LANG`, `TMPDIR`, claude's own variables (`ANTHROPIC_API_KEY`,
`CLAUDE_CODE_*`) and the run binding. `GH_TOKEN` and `GITHUB_TOKEN` are never passed. The wrappers use your own gh
sign-in, as gh's configuration and keychain provide it.

## GitNexus

GitNexus can read the repos it has indexed, and `auto` mode turns it off whenever the authors are `anyone`, because
those PRs come from strangers. Set `gitnexus = "on"` explicitly to override. Only the seven read-only GitNexus tools
listed above are allowed; the tools that rename, sync groups or query across repos are not.

## Rules file

The rules file is visible to the reviewer and may be quoted in public comments. Never put secrets, tokens, internal
hostnames or private data in it.

## Your own PRs

Skipped unless `include_own = true`. When they are reviewed, the review is a COMMENT with the verdict in its first
line, because GitHub does not accept APPROVE or REQUEST_CHANGES on your own PR.

## Collaborators only, by default

A PR author is reviewed only when they have write, maintain or admin access, and that permission must be readable.
Without push access, the permission cannot be read, and those PRs are skipped with that reason. For those authors,
or any others, list the logins in `authors`.

## PR text is untrusted

Titles, bodies, comments, diffs and file contents are data. The skill says so, and the wrappers label PR text as
data in their output. This is defence in depth, not a guarantee: a convincing PR can still get a poor review posted.
That is why `posting = "comment"` is the default, and why dry runs exist.

## Posting is visible

Reviews appear under your GitHub account. "Run now" in the app asks for confirmation when any repo uses
`posting = "review"`.

## Local state

The run file holds PR numbers, titles, authors, verdicts and token counts. It holds no tokens, and the session
transcript stays in Claude Code's own folder.

