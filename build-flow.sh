#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenpipeFlow"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"

cd "$PROJECT_DIR"

echo "==> Building $APP_NAME (universal)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/ScreenpipeFlowInfo.plist "$APP_BUNDLE/Contents/Info.plist"

# SwiftPM generates a resource bundle named Package_Target.bundle. For us the
# package is ScreenpipeMenu and the target is ScreenpipeFlow.
SPM_BUNDLE="$PROJECT_DIR/.build/apple/Products/Release/ScreenpipeMenu_ScreenpipeFlow.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
else
    echo "WARNING: resource bundle not found at $SPM_BUNDLE — synthesis-prompt.md may be missing at runtime"
fi

# Match Tool 1's signing strategy: use the self-signed dev cert if present,
# else fall back to ad-hoc (still launches fine; TCC just re-prompts on each rebuild).
CERT_NAME="ScreenpipeMenu Local Dev"
CERT_LINE=$(security find-identity -p basic login.keychain 2>/dev/null | grep "$CERT_NAME" || true)
CERT_SHA=$(echo "$CERT_LINE" | awk '{print $2}' | head -1)

if [ -n "$CERT_SHA" ]; then
    SIGN_IDENTITY="$CERT_SHA"
    echo "==> Codesigning with '$CERT_NAME' ($CERT_SHA)"
else
    SIGN_IDENTITY="-"
    echo "==> Codesigning ad-hoc (run ./bootstrap-cert.sh once for stable signing)"
fi

codesign --sign "$SIGN_IDENTITY" --force --identifier com.mengo.screenpipeflow "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
