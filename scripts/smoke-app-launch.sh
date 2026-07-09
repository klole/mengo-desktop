#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MENGO_APP_LAUNCH_SMOKE_APP:-$ROOT/MengoDesktop.app}"
EXECUTABLE="$APP/Contents/MacOS/MengoDesktop"
HELPER="$APP/Contents/Helpers/screenpipe"
TIMEOUT_SECONDS="${MENGO_APP_LAUNCH_TIMEOUT_SECONDS:-20}"
HOLD_SECONDS="${MENGO_APP_LAUNCH_HOLD_SECONDS:-3}"
REAL_HOME="$HOME"
LOG_FILE="${MENGO_APP_LAUNCH_LOG:-$REAL_HOME/Library/Logs/MengoDesktop/app.log}"
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/mengo-launch-home.XXXXXX")"
PID=""
BEFORE_HELPERS=""

helper_pids() {
    ps ax -o pid=,command= | awk -v helper="$HELPER" 'index($0, helper) > 0 { print $1 }'
}

cleanup() {
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$PID" 2>/dev/null || true
    fi
    for helper_pid in $(helper_pids); do
        case " $BEFORE_HELPERS " in
            *" $helper_pid "*) ;;
            *) kill "$helper_pid" 2>/dev/null || true ;;
        esac
    done
    rm -rf "$TMP_HOME"
}
trap cleanup EXIT

fail() {
    echo "ERROR: $*" >&2
    if [ -f "$LOG_FILE" ]; then
        echo "==> app.log" >&2
        tail -n 160 "$LOG_FILE" >&2
    fi
    exit 1
}

[ -d "$APP" ] || fail "missing app bundle: $APP"
[ -x "$EXECUTABLE" ] || fail "missing executable: $EXECUTABLE"

echo "==> Launching Mengo Desktop in a temporary local-preview home"
BEFORE_HELPERS="$(helper_pids | tr '\n' ' ')"
(
    cd "$ROOT"
    HOME="$TMP_HOME" \
    MENGO_PREVIEW_ACCOUNT="${MENGO_PREVIEW_ACCOUNT:-pro}" \
    MENGO_DISABLE_START_RECORDING_ON_LAUNCH=1 \
    "$EXECUTABLE"
) &
PID="$!"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! kill -0 "$PID" 2>/dev/null; then
        wait "$PID" || true
        fail "Mengo Desktop exited before launch smoke completed"
    fi
    if [ -f "$LOG_FILE" ] && grep -F "app launched, pid=$PID" "$LOG_FILE" >/dev/null; then
        sleep "$HOLD_SECONDS"
        kill -0 "$PID" 2>/dev/null || fail "Mengo Desktop exited during launch hold"
        echo "Mengo Desktop launch smoke passed."
        exit 0
    fi
    sleep 0.2
done

fail "timed out waiting for launch log: $LOG_FILE"
