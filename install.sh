#!/usr/bin/env bash
# install.sh — installs ScreenpipeMenu (always-on recorder) AND ScreenpipeFlow
# (demonstration-to-skill recorder) into ~/Applications, then launches both.
# Run from inside this repo. No sudo needed. macOS 15 / arm64 only.
set -euo pipefail

APPS_DIR="$HOME/Applications"
MENU_APP="$APPS_DIR/ScreenpipeMenu.app"
FLOW_APP="$APPS_DIR/ScreenpipeFlow.app"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "==> Checking prerequisites"

MACOS_MAJOR=$(sw_vers -productVersion | awk -F. '{ print $1 }')
if [ "$MACOS_MAJOR" -lt 15 ]; then
    echo "ERROR: needs macOS 15 (Sequoia) or later. You have $(sw_vers -productVersion)."
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "ERROR: this build is Apple-Silicon only (arm64). You're on $ARCH."
    echo "       Rebuild from source with the matching arch — see README.md."
    exit 1
fi

mkdir -p "$APPS_DIR"
rm -rf "$MENU_APP" "$FLOW_APP"

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
REPO_SLUG=$(echo "$ORIGIN_URL" | sed -E 's|.*github.com[/:]([^/]+/[^/.]+)(\.git)?|\1|')

# Both apps share a release. We download the asset names containing each app name.
fetch_release_url() {
    local app_name=$1
    if [ -z "$REPO_SLUG" ]; then echo ""; return; fi
    curl -fsSL "https://api.github.com/repos/$REPO_SLUG/releases/latest" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        if a['name'].startswith('$app_name') and a['name'].endswith('.zip'):
            print(a['browser_download_url']); break
except Exception:
    pass
" || echo ""
}

install_app_from_url() {
    local url=$1
    local dest=$2
    local zipname=$(basename "$url")
    local appname=$(basename "$dest")
    local tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN
    curl -fsSL "$url" -o "$tmp/$zipname"
    ditto -x -k "$tmp/$zipname" "$tmp/extracted"
    mv "$tmp/extracted/$appname" "$dest"
}

build_from_source() {
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
    mv ScreenpipeMenu.app "$MENU_APP"
    ./build-flow.sh
    mv ScreenpipeFlow.app "$FLOW_APP"
}

MENU_URL=$(fetch_release_url "ScreenpipeMenu")
FLOW_URL=$(fetch_release_url "ScreenpipeFlow")

if [ -n "$MENU_URL" ] && [ -n "$FLOW_URL" ]; then
    echo "==> Downloading pre-built releases"
    echo "    Menu: $MENU_URL"
    echo "    Flow: $FLOW_URL"
    install_app_from_url "$MENU_URL" "$MENU_APP"
    install_app_from_url "$FLOW_URL" "$FLOW_APP"
else
    echo "==> No prebuilt release with both apps — building from source"
    build_from_source
fi

echo "==> Removing quarantine"
xattr -dr com.apple.quarantine "$MENU_APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$FLOW_APP" 2>/dev/null || true

echo "==> Stopping any prior instances"
osascript -e 'tell application "ScreenpipeMenu" to quit' 2>/dev/null || true
osascript -e 'tell application "ScreenpipeFlow" to quit' 2>/dev/null || true
pkill -f "ScreenpipeMenu" 2>/dev/null || true
pkill -f "ScreenpipeFlow" 2>/dev/null || true
pkill -f "Helpers/screenpipe record" 2>/dev/null || true
sleep 2

echo "==> Launching ScreenpipeMenu (recorder)"
open "$MENU_APP"

echo "==> Waiting 10s for screenpipe to come online before launching ScreenpipeFlow…"
sleep 10
echo "==> Launching ScreenpipeFlow (skill recorder)"
open "$FLOW_APP"

cat <<'EOF'

✓ Installed:
  ~/Applications/ScreenpipeMenu.app   (always-on recorder)
  ~/Applications/ScreenpipeFlow.app   (demonstration-to-skill recorder)

Two things you need to do RIGHT NOW:

  1. A Screen Recording permission dialog will appear (or has already).
     Click "Open System Settings", find ScreenpipeMenu in the list,
     toggle it ON, then close System Settings.

  2. Accept the Microphone prompt.

After both are granted, look in your menu bar (top-right):
  - ScreenpipeMenu turns green and says "Recording" within ~15 seconds
  - ScreenpipeFlow shows a "Flow" label — click for Start/Grab options

To use ScreenpipeFlow:
  - "Start recording" → narrate your task → Stop → wait ~30s for synthesis
  - "Grab last 5 minutes…" → pick a start point → continue narrating

Skills land in ~/.claude/skills/<slug>/ and are invokable via Claude Code.

EOF
