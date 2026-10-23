# Changelog

## 1.3.3

- New setups hold each review for you to post, and start on Sonnet with five PRs a sweep. Existing configs are unchanged.
- Schedule's monthly token estimate comes from your real sweeps; it shows "—" until three have finished.
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
