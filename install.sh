#!/usr/bin/env bash
# install.sh — installs Mengo Desktop into ~/Applications, then launches it.
# Run from inside this repo. No sudo needed. macOS 15 / arm64 only.
set -euo pipefail

APP_NAME="MengoDesktop"
APPS_DIR="$HOME/Applications"
APP_DEST="$APPS_DIR/$APP_NAME.app"
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
    echo "ERROR: Apple Silicon (arm64) only. You're on $ARCH."
    exit 1
fi

mkdir -p "$APPS_DIR"

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
REPO_SLUG=$(echo "$ORIGIN_URL" | sed -E 's|.*github.com[/:]([^/]+/[^/.]+)(\.git)?|\1|')

# Find the signed app archive and its checksum in the latest GitHub release.
fetch_release_assets() {
    if [ -z "$REPO_SLUG" ]; then return; fi
    curl -fsSL "https://api.github.com/repos/$REPO_SLUG/releases/latest" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    assets = {a['name']: a['browser_download_url'] for a in d.get('assets', [])}
    archive = assets.get('$APP_NAME.zip')
    checksum = assets.get('$APP_NAME.zip.sha256')
    if archive and checksum:
        print(archive, checksum)
except Exception:
    pass
" || true
}

install_app_from_url() {
    local url=$1
    local checksum_url=$2
    local zipname; zipname=$(basename "$url")
    local tmp; tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN
    curl -fsSL "$url" -o "$tmp/$zipname"
    curl -fsSL "$checksum_url" -o "$tmp/$APP_NAME.zip.sha256"
    (cd "$tmp" && shasum -a 256 -c "$APP_NAME.zip.sha256")
    ditto -x -k "$tmp/$zipname" "$tmp/extracted"
    local candidate="$tmp/extracted/$APP_NAME.app"
    [ -d "$candidate" ] || { echo "ERROR: release archive does not contain $APP_NAME.app"; exit 1; }
    codesign --verify --deep --strict "$candidate"
    spctl --assess --type execute "$candidate"
    rm -rf "$APP_DEST"
    ditto "$candidate" "$APP_DEST"
}

build_from_source() {
    if ! command -v swift >/dev/null 2>&1; then
        echo "ERROR: swift not found. Install Xcode 16+ from the App Store, then run:"
        echo "       xcode-select --install"
        exit 1
    fi
    SWIFT_MAJOR=$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+' | awk '{print $3}' || echo 0)
    if [ "${SWIFT_MAJOR:-0}" -lt 6 ]; then
        echo "ERROR: Swift 6+ required (found ${SWIFT_MAJOR}). Update Xcode to 16+."
        exit 1
    fi
    ./build-mengo.sh
    local tmp; tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN
    ditto -x -k MengoDesktop.zip "$tmp"
    codesign --verify --deep --strict "$tmp/MengoDesktop.app"
    rm -rf "$APP_DEST"
    ditto "$tmp/MengoDesktop.app" "$APP_DEST"
    codesign --verify --deep --strict "$APP_DEST"
}

read -r URL CHECKSUM_URL < <(fetch_release_assets || true) || true
URL=${URL:-}
CHECKSUM_URL=${CHECKSUM_URL:-}

if [ -n "$URL" ]; then
    echo "==> Downloading prebuilt release: $URL"
    install_app_from_url "$URL" "$CHECKSUM_URL"
else
    echo "==> No verified prebuilt release found — building from source"
    build_from_source
fi

echo "==> Stopping any prior instances"
osascript -e 'tell application "MengoDesktop" to quit' 2>/dev/null || true
pkill -f "MengoDesktop.app/Contents/MacOS" 2>/dev/null || true
pkill -f "Helpers/screenpipe record" 2>/dev/null || true
sleep 2

echo "==> Launching Mengo Desktop"
open "$APP_DEST"

cat <<'EOF'

✓ Installed: ~/Applications/MengoDesktop.app

Two things to do right now:

  1. macOS will ask for Screen Recording permission.
     Click "Open System Settings", find MengoDesktop in the list,
     toggle it ON, then close System Settings.

  2. Accept the Microphone prompt when it appears.

After both are granted, Mengo will start recording locally — nothing
leaves your Mac. Open the app to see Memory, Flow, Library, and Studio.

EOF
