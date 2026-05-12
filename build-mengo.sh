#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MengoDesktop"
BUNDLE_ID="ai.mengo.desktop"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.png"

cd "$PROJECT_DIR"

echo "==> Building $APP_NAME (universal)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/MengoDesktopInfo.plist "$APP_BUNDLE/Contents/Info.plist"

# Generate AppIcon.icns from the committed source PNG (single source of truth).
if [ -f "$ICON_SRC" ]; then
    echo "==> Generating AppIcon.icns from Resources/AppIcon.png"
    TMPDIR_ICON="$(mktemp -d)"
    ICONSET="$TMPDIR_ICON/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$TMPDIR_ICON"
else
    echo "WARNING: $ICON_SRC not found — building without a custom app icon"
fi

# Signing: prefer the self-signed dev cert (stable identity across rebuilds —
# matters once later phases rely on TCC grants surviving), else ad-hoc.
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

codesign --sign "$SIGN_IDENTITY" --force --identifier "$BUNDLE_ID" "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
