#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MengoDesktop"
BUNDLE_ID="ai.mengo.desktop"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.png"
CACHE_DIR="$PROJECT_DIR/.build-cache"

cd "$PROJECT_DIR"

# screenpipe ships per-arch CLI packages on npm. Bundle the one matching this host.
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    arm64)  SP_ARCH="arm64" ;;
    x86_64) SP_ARCH="x64" ;;
    *) echo "unsupported arch: $HOST_ARCH"; exit 1 ;;
esac
ZIP_OUT="$PROJECT_DIR/$APP_NAME-macos-$HOST_ARCH.zip"

echo "==> Resolving screenpipe latest version"
SP_VERSION=$(curl -fsSL https://registry.npmjs.org/screenpipe/latest \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
SP_TARBALL_URL="https://registry.npmjs.org/@screenpipe/cli-darwin-$SP_ARCH/-/cli-darwin-$SP_ARCH-$SP_VERSION.tgz"
echo "    version: $SP_VERSION  arch: $SP_ARCH"

mkdir -p "$CACHE_DIR"
TARBALL="$CACHE_DIR/screenpipe-$SP_VERSION-$SP_ARCH.tgz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading screenpipe tarball"
    curl -fsSL "$SP_TARBALL_URL" -o "$TARBALL"
fi

echo "==> Building $APP_NAME ($HOST_ARCH)"
swift build -c release --arch "$HOST_ARCH" --product "$APP_NAME"
BUILD_PRODUCT=".build/$HOST_ARCH-apple-macosx/release/$APP_NAME"
if [ ! -f "$BUILD_PRODUCT" ]; then
    echo "ERROR: expected built product at $BUILD_PRODUCT"
    exit 1
fi

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT" "$PROJECT_DIR/$APP_NAME.zip"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

cp "$BUILD_PRODUCT" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/MengoDesktopInfo.plist "$APP_BUNDLE/Contents/Info.plist"
cp -X Resources/MengoLogo.png "$APP_BUNDLE/Contents/Resources/MengoLogo.png"   # -X: don't copy extended attrs (codesign rejects FinderInfo/resource forks)
cp -X Resources/synthesis-prompt.md "$APP_BUNDLE/Contents/Resources/synthesis-prompt.md"   # Flow's bootstrap synthesis prompt (loaded via Bundle.main)

# Embed the screenpipe binary + its Metal library. Tarball layout: package/bin/{screenpipe, mlx.metallib}
tar -xzf "$TARBALL" -C "$APP_BUNDLE/Contents/Helpers" --strip-components=2 package/bin/
chmod +x "$APP_BUNDLE/Contents/Helpers/screenpipe"

# Generate AppIcon.icns from the committed source PNG.
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

# Signing. Prefer the self-signed dev cert (stable identity across rebuilds → TCC
# grants survive; the bundled helper inherits them), else ad-hoc. The helper gets
# the SAME identifier as the .app so macOS treats it as part of Mengo Desktop.
CERT_NAME="${MENGO_SIGNING_IDENTITY:-Mengo Desktop Local Dev}"
CERT_LINE=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$CERT_NAME" || true)
CERT_SHA=$(echo "$CERT_LINE" | awk '{print $2}' | head -1)
if [ -n "$CERT_SHA" ]; then
    SIGN_IDENTITY="$CERT_SHA"
    echo "==> Codesigning with '$CERT_NAME' ($CERT_SHA)"
else
    SIGN_IDENTITY="-"
    echo "==> Codesigning ad-hoc (run ./bootstrap-cert.sh once for stable signing)"
fi

# Strip any stray extended attributes (Finder info, resource forks) — codesign refuses them.
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

codesign --remove-signature "$APP_BUNDLE/Contents/Helpers/screenpipe" 2>/dev/null || true
SIGN_FLAGS=(--sign "$SIGN_IDENTITY" --force)
if [ "${MENGO_SIGN_FOR_NOTARIZATION:-0}" = "1" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "ERROR: MENGO_SIGN_FOR_NOTARIZATION=1 requires a Developer ID signing identity"
        exit 1
    fi
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

codesign "${SIGN_FLAGS[@]}" "$APP_BUNDLE/Contents/Helpers/mlx.metallib"
codesign "${SIGN_FLAGS[@]}" --identifier "$BUNDLE_ID" "$APP_BUNDLE/Contents/Helpers/screenpipe"
codesign "${SIGN_FLAGS[@]}" --identifier "$BUNDLE_ID" "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  screenpipe v$SP_VERSION ($SP_ARCH) embedded"
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
