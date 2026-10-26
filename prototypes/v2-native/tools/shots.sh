#!/bin/zsh
# Drives the running prototype through each screen and saves screenshots to shots/.
# Windows are composited over the wallpaper only (ScreenCaptureKit), never other apps, so the glass reads true.
setopt nullglob
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
[[ .build/cap -nt tools/cap.swift ]] || swiftc -O -o .build/cap tools/cap.swift 2>/dev/null
S=$PWD/shots; mkdir -p $S; rm -f $S/*.png
C=.build/cap
cmd() { $C send "$1"; sleep ${2:-1}; }
grab() { $C shot "$S/$1.png" "$2" >/dev/null && echo "$S/$1.png"; }

cmd "scenario:Needs you"; cmd "page:Inbox"; cmd activate
grab 01-inbox-needs-you Inbox
cmd "pr:web-1276"; grab 02-pr-inspector-team Inbox
cmd "pr:api-1253"; grab 03-pr-inspector-fix Inbox
cmd "page:Inbox"
# Signature: hold Post review, the pane fills with light, glides into Done today.
$C send "hold:web-1276"; sleep 0.25; grab 04-signature-1-fill Inbox; sleep 0.35; grab 04-signature-2-glide Inbox; sleep 0.12; grab 04-signature-3-settle Inbox; sleep 1.2; grab 04-signature-4-landed Inbox
# Selecting a row: its glass grows into the inspector.
cmd "scenario:Needs you"; $C send "selectshots:api-1253:/x"; sleep 0.62; grab 05-morph-1 Inbox; grab 05-morph-2 Inbox; sleep 1; grab 05-morph-3 Inbox
cmd "scenario:Checking" 1.6; grab 06-inbox-checking-tracer Inbox
cmd "scenario:All good" 1.5; grab 07-inbox-all-clear Inbox
cmd "scenario:Problem"; grab 08-inbox-problem Inbox
cmd "scenario:Paused"; grab 09-inbox-paused Inbox
cmd "scenario:Needs you"; cmd "page:PRs"; cmd "your:0"; grab 10-prs-team PRs
cmd "your:1"; grab 11-prs-yours PRs
cmd "page:Activity"; cmd activate; grab 12-activity Activity
cmd "page:Repos"; cmd activate; grab 13-repos Repos
cmd "page:Inbox"; cmd popover; grab 14-popover-needs-you popover
cmd popover 0.4; cmd "scenario:Checking" 0.3; cmd popover 1.4; grab 15-popover-checking popover
cmd popover 0.4; cmd "scenario:Problem" 0.3; cmd popover; grab 16-popover-problem popover
cmd popover 0.4; cmd "scenario:Paused" 0.3; cmd popover; grab 17-popover-paused popover
cmd popover 0.4
cmd "glyphs:$S/18-menu-bar-glyphs.png"; echo "$S/18-menu-bar-glyphs.png"
cmd "settings:general"; grab 19-settings-general General
cmd "settings:behaviour"; grab 20-settings-behaviour Behaviour
cmd "settings:schedule"; grab 21-settings-schedule Schedule
cmd "scenario:First launch"; cmd activate; grab 22-onboarding Inbox
cmd "scenario:Needs you"; cmd closeothers; cmd "page:Inbox"; cmd activate
# Stuck: a plain Try again (a click), also in Your PRs and the inspector timeline.
cmd "scenario:Stuck"; cmd "page:Inbox"; grab 23-inbox-stuck Inbox
cmd "pr:api-1310"; grab 24-pr-inspector-stuck Inbox
cmd "page:PRs"; cmd "your:1"; grab 25-prs-yours-stuck PRs
# Nudging a slow reviewer: Ping Gadi is a hold (it posts a comment), then "Pinged today" in Activity.
cmd "scenario:Slow reviewer"; cmd "page:Inbox"; grab 26-inbox-ping Inbox
cmd "pr:api-1305"; grab 27-pr-inspector-ping Inbox
cmd "page:Inbox"; $C send "hold:api-1305"; sleep 2.6
cmd "page:Activity"; grab 28-activity-pinged Activity
# Holding back for the usage reserve or quiet hours: the line goes dotted and the sentence says why.
cmd "scenario:Holding back"; cmd "page:Inbox"; grab 29-inbox-holding-back Inbox
cmd popover; grab 30-popover-holding-back popover; cmd popover 0.4
cmd "settings:schedule"; grab 31-settings-schedule-holding Schedule
cmd "scenario:Quiet hours"; cmd "page:Inbox"; cmd activate; grab 32-inbox-quiet-hours Inbox
cmd popover; grab 33-popover-quiet-hours popover; cmd popover 0.4
# The same smoked glass over a dark desktop (a prototype backdrop window, the real wallpaper is untouched).
cmd "scenario:Needs you"; cmd "page:Inbox"; cmd activate; cmd "backdrop:1"; grab 34-inbox-dark-desktop Inbox
cmd popover; grab 35-popover-dark-desktop popover; cmd popover 0.4; cmd "backdrop:0"
cmd "scenario:Needs you"; cmd closeothers; cmd "page:Inbox"; cmd activate
