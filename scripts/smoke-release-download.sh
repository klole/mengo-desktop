#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-klole/mengo-desktop}"
RELEASE_TAG="${MENGO_RELEASE_TAG:-v0.1.0-preview}"
ASSET="${MENGO_RELEASE_ASSET:-MengoDesktop-macos-arm64.zip}"
RELEASE_NOTES="$ROOT/docs/release/v0.1.0-preview.md"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v ditto >/dev/null 2>&1 || fail "ditto is required"

TMPDIR_SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/mengo-release-download.XXXXXX")"
trap 'rm -rf "$TMPDIR_SMOKE"' EXIT

echo "==> Downloading release asset"
gh release download "$RELEASE_TAG" \
    --repo "$REPO" \
    --pattern "$ASSET" \
    --dir "$TMPDIR_SMOKE" \
    --clobber

DOWNLOADED_ZIP="$TMPDIR_SMOKE/$ASSET"
[ -f "$DOWNLOADED_ZIP" ] || fail "downloaded asset not found: $DOWNLOADED_ZIP"

EXPECTED_SHA="$(grep -Eo "^[0-9a-f]{64}  $ASSET$" "$RELEASE_NOTES" | awk '{print $1}' | tail -1)"
[ -n "$EXPECTED_SHA" ] || fail "could not find expected checksum for $ASSET in release notes"

ACTUAL_SHA="$(shasum -a 256 "$DOWNLOADED_ZIP" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    fail "downloaded checksum $ACTUAL_SHA does not match expected $EXPECTED_SHA"
fi
echo "Downloaded checksum matches: $ACTUAL_SHA"

echo
echo "==> Extracting downloaded asset"
EXTRACT_DIR="$TMPDIR_SMOKE/unpacked"
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$DOWNLOADED_ZIP" "$EXTRACT_DIR"

APP="$EXTRACT_DIR/MengoDesktop.app"
[ -d "$APP" ] || fail "MengoDesktop.app not found in downloaded zip"

echo
echo "==> Verifying downloaded app signature"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Downloaded app codesign verification passed."

echo
echo "==> Checking Gatekeeper status"
SPCTL_OUT="$TMPDIR_SMOKE/spctl.out"
if spctl --assess --type execute -vv "$APP" >"$SPCTL_OUT" 2>&1; then
    echo "Downloaded app passed Gatekeeper assessment."
else
    cat "$SPCTL_OUT"
    if grep -qi "not notarized" "$RELEASE_NOTES" && grep -qi "rejected" "$SPCTL_OUT"; then
        echo "Downloaded app Gatekeeper rejection is expected for the non-notarized preview."
    else
        fail "downloaded app Gatekeeper result is not documented as expected"
    fi
fi

if [ "${MENGO_RELEASE_DOWNLOAD_LAUNCH_SMOKE:-0}" = "1" ]; then
    echo
    echo "==> Launching downloaded app"
    MENGO_APP_LAUNCH_SMOKE_APP="$APP" "$ROOT/scripts/smoke-app-launch.sh"
else
    echo "SKIP: set MENGO_RELEASE_DOWNLOAD_LAUNCH_SMOKE=1 to launch the downloaded app in local-preview mode"
fi

echo
echo "Published release download smoke passed."
