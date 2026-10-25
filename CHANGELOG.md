# Changelog

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
