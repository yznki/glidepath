# Changelog

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
