#!/usr/bin/env bash
# install.sh — installs ScreenpipeMenu into ~/Applications and launches it.
# Run from inside this repo.
# No sudo needed. macOS 15 / arm64 only.
set -euo pipefail

APPS_DIR="$HOME/Applications"
APP_PATH="$APPS_DIR/ScreenpipeMenu.app"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "==> Checking prerequisites"

MACOS_MAJOR=$(sw_vers -productVersion | awk -F. '{ print $1 }')
if [ "$MACOS_MAJOR" -lt 15 ]; then
    echo "ERROR: ScreenpipeMenu needs macOS 15 (Sequoia) or later. You have $(sw_vers -productVersion)."
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "ERROR: this build is Apple-Silicon only (arm64). You're on $ARCH."
    echo "       Rebuild from source with the matching arch — see README.md."
    exit 1
fi

# Did the maintainer ship a pre-built release? If yes, use that. Otherwise build from source.
mkdir -p "$APPS_DIR"
rm -rf "$APP_PATH"

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
REPO_SLUG=$(echo "$ORIGIN_URL" | sed -E 's|.*github.com[/:]([^/]+/[^/.]+)(\.git)?|\1|')

RELEASE_ZIP_URL=""
if [ -n "$REPO_SLUG" ]; then
    RELEASE_ZIP_URL=$(curl -fsSL "https://api.github.com/repos/$REPO_SLUG/releases/latest" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        if a['name'].endswith('.zip'):
            print(a['browser_download_url']); break
except Exception:
    pass
" || echo "")
fi

if [ -n "$RELEASE_ZIP_URL" ]; then
    echo "==> Downloading pre-built release"
    echo "    $RELEASE_ZIP_URL"
    TMP=$(mktemp -d)
    trap "rm -rf '$TMP'" EXIT
    curl -fsSL "$RELEASE_ZIP_URL" -o "$TMP/ScreenpipeMenu.zip"
    ditto -x -k "$TMP/ScreenpipeMenu.zip" "$TMP/extracted"
    mv "$TMP/extracted/ScreenpipeMenu.app" "$APP_PATH"
else
    echo "==> No release found — building from source"
    if ! command -v swift >/dev/null 2>&1; then
        echo "ERROR: swift not found. Install Xcode 16+ from the App Store, then run:"
        echo "       xcode-select --install"
        echo "       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi
    SWIFT_MAJOR=$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+' | awk '{print $3}' || echo 0)
    if [ "${SWIFT_MAJOR:-0}" -lt 6 ]; then
        echo "ERROR: Swift 6+ required (found ${SWIFT_MAJOR}). Update Xcode to 16+."
        exit 1
    fi
    ./build.sh
    mv ScreenpipeMenu.app "$APP_PATH"
fi

echo "==> Removing quarantine (unsigned app — Gatekeeper bypass)"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "==> Stopping any prior instance"
osascript -e 'tell application "ScreenpipeMenu" to quit' 2>/dev/null || true
pkill -f "ScreenpipeMenu" 2>/dev/null || true
pkill -f "Helpers/screenpipe record" 2>/dev/null || true
sleep 2

echo "==> Launching"
open "$APP_PATH"

cat <<'EOF'

✓ Installed at ~/Applications/ScreenpipeMenu.app and launched.

Two things you need to do RIGHT NOW:

  1. A Screen Recording permission dialog will appear (or has already).
     Click "Open System Settings", find ScreenpipeMenu in the list,
     toggle it ON, then close System Settings.

  2. Accept the Microphone prompt.

After both are granted, look in your menu bar (top-right): within ~15
seconds the icon should turn green and say "Recording".

Click the icon for status, pause/resume controls, and access to your
data folder (~/.screenpipe).

EOF
