#!/usr/bin/env bash
# install.sh - installs MengoDesktop into ~/Applications and launches it.
set -euo pipefail

APP_NAME="MengoDesktop"
APP_BUNDLE="$APP_NAME.app"
ZIP_PREFIX="$APP_NAME"
APPS_DIR="$HOME/Applications"
DEST_APP="$APPS_DIR/$APP_BUNDLE"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$REPO_DIR"

echo "==> Checking prerequisites"

MACOS_MAJOR=$(sw_vers -productVersion | awk -F. '{ print $1 }')
if [ "$MACOS_MAJOR" -lt 15 ]; then
    echo "ERROR: Mengo Desktop needs macOS 15 (Sequoia) or later. You have $(sw_vers -productVersion)."
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    arm64|x86_64) ;;
    *)
        echo "ERROR: unsupported architecture: $ARCH"
        exit 1
        ;;
esac

mkdir -p "$APPS_DIR"

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
REPO_SLUG=$(echo "$ORIGIN_URL" | sed -E 's|.*github.com[/:]([^/]+/[^/.]+)(\.git)?|\1|')

fetch_release_url() {
    if [ -z "$REPO_SLUG" ]; then echo ""; return; fi
    curl -fsSL "https://api.github.com/repos/$REPO_SLUG/releases/latest" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        name = a.get('name', '')
        if name.startswith('$ZIP_PREFIX') and name.endswith('.zip'):
            print(a['browser_download_url'])
            break
except Exception:
    pass
" || echo ""
}

install_app_from_url() {
    local url=$1
    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    echo "==> Downloading $url"
    curl -fsSL "$url" -o "$tmp/$APP_NAME.zip"
    ditto -x -k "$tmp/$APP_NAME.zip" "$tmp/extracted"

    if [ ! -d "$tmp/extracted/$APP_BUNDLE" ]; then
        echo "ERROR: release archive did not contain $APP_BUNDLE"
        exit 1
    fi

    rm -rf "$DEST_APP"
    mv "$tmp/extracted/$APP_BUNDLE" "$DEST_APP"
}

build_from_source() {
    if ! command -v swift >/dev/null 2>&1; then
        echo "ERROR: swift not found. Install Xcode 16+ and rerun ./install.sh."
        exit 1
    fi

    SWIFT_MAJOR=$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+' | awk '{print $3}' || echo 0)
    if [ "${SWIFT_MAJOR:-0}" -lt 6 ]; then
        echo "ERROR: Swift 6+ required. Found Swift ${SWIFT_MAJOR:-unknown}."
        exit 1
    fi

    ./build-mengo.sh
    rm -rf "$DEST_APP"
    mv "$APP_BUNDLE" "$DEST_APP"
}

RELEASE_URL=$(fetch_release_url)

if [ -n "$RELEASE_URL" ]; then
    install_app_from_url "$RELEASE_URL"
else
    echo "==> No matching MengoDesktop release asset found; building from source"
    build_from_source
fi

echo "==> Removing quarantine metadata"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "==> Stopping prior Mengo Desktop instances"
osascript -e 'tell application "Mengo Desktop" to quit' 2>/dev/null || true
pkill -f "MengoDesktop" 2>/dev/null || true
pkill -f "Mengo Desktop" 2>/dev/null || true
pkill -f "Helpers/screenpipe record" 2>/dev/null || true
sleep 2

echo "==> Launching Mengo Desktop"
open "$DEST_APP"

cat <<EOF

Installed:
  $DEST_APP

Next steps:

1. Grant Screen Recording permission to Mengo Desktop when macOS prompts.
2. Grant Microphone permission to Mengo Desktop when macOS prompts.
3. If macOS blocks this preview build, right-click the app and choose Open.

Local data:
  screenpipe data: ~/.screenpipe
  app logs:        ~/Library/Logs/MengoDesktop

Runtime setup:
  Claude Code users should run:
    claude mcp add screenpipe -s user -- npx -y screenpipe-mcp

EOF
