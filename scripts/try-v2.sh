#!/usr/bin/env bash
# Runs this checkout's app beside the installed Glidepath without touching it: its own bundle id and name, and a
# scratch HOME, so its config, state, app lock and logs live under /tmp. A scratch HOME also means no gh sign-in (so
# nothing can post), and the app loads no launchd job and registers no login item outside the real home.
#
#   scripts/try-v2.sh empty   no config: onboarding opens
#   scripts/try-v2.sh demo    the window fixtures as config and runs, dry run on: Needs you has items
#   scripts/try-v2.sh stop    quits the try-out app only
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=/tmp/glidepath-v2try
APP="$ROOT/Glidepath v2 (try).app"
BIN="$APP/Contents/MacOS/glidepath"
SCRATCH="$ROOT/home"

stop() {
    # Matches only processes started from $ROOT: the try-out app and anything it spawned. Never the installed app.
    pkill -f "^(/private)?$ROOT/" || true
}

build() {
    ./make-app.sh
    rm -rf "$APP"
    mkdir -p "$ROOT"
    cp -R build/Glidepath.app "$APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.glidepath.app.v2try" \
        -c "Set :CFBundleName Glidepath v2 (try)" -c "Set :CFBundleDisplayName Glidepath v2 (try)" "$APP/Contents/Info.plist"
    codesign --force --deep -s - "$APP"
}

# A clean environment: the scratch HOME, a PATH with the usual tools, and no tokens or XDG overrides from this shell.
scratch() {
    env -i HOME="$SCRATCH" USER="$USER" LOGNAME="${LOGNAME:-$USER}" TMPDIR="${TMPDIR:-/tmp/}" LANG="${LANG:-en_US.UTF-8}" \
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$@"
}

case "${1:-}" in
    empty|demo)
        stop
        build
        rm -rf "$SCRATCH"
        mkdir -p "$SCRATCH"
        if [[ "$1" == demo ]]; then scratch "$BIN" --seed-demo; fi
        scratch nohup "$BIN" >"$ROOT/app.log" 2>&1 &
        echo "started $APP (HOME=$SCRATCH, log $ROOT/app.log); stop with: $0 stop"
        ;;
    stop)
        stop
        echo "stopped"
        ;;
    *)
        echo "usage: $0 empty|demo|stop" >&2
        exit 2
        ;;
esac
