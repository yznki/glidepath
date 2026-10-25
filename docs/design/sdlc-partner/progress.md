# SDLC partner build progress

Resume here after a compaction. One line per step; decisions and open issues below.

## Status

| Phase | Step | Status | Commit |
|---|---|---|---|
| 1.6 | branch sdlc-1.6, build design `notes/1.6.md` | done | |
| 1.6 | H1 core: config, usage guard, push guard, approach, tend state, autopilot, playbook + tests | in progress | |

## Decisions (Yazan should know)

- `max_usd_per_session` is whole dollars: the TOML reader has no floats.
- Every check counts as required for the CI gate (GraphQL `isRequired` needs a per-PR argument).
- Usage guard has no per-task estimate yet: it refuses at `100 - reserve` utilization; estimates once History calibrates.
- Quiet-hours question is in Settings → Tending, not onboarding (tending is off for new installs anyway).
- Autopilot toggle only writes `autopilot = true`; `Autopilot.swift` treats push/disagree/merge as their autopilot
  values at decision time instead of rewriting those keys.
- Turning tending on (Settings) writes `advisor = "opus"`; push stays `until_approved` until the user picks.
- `claude_config_dir` is top level: the separate account runs reviews and tending.
- Playbook commands record count and date, not duration.

## Open issues

- none yet
