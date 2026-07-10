#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MengoDesktop"
BUNDLE_ID="ai.mengo.desktop"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.png"
CACHE_DIR="$PROJECT_DIR/.build-cache"

cd "$PROJECT_DIR"

# screenpipe ships per-architecture CLI packages on npm. The app executable and
# recorder helper must match, so this script produces a native-architecture app.
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    arm64)  SP_ARCH="arm64" ;;
    x86_64) SP_ARCH="x64" ;;
    *) echo "unsupported arch: $HOST_ARCH"; exit 1 ;;
esac

# Pin screenpipe — 0.3.336+ exits silently within ~30s for us (cause TBD).
# Bump this only after confirming a newer release runs cleanly for ≥ 5 minutes.
SP_VERSION="0.3.327"
SP_TARBALL_SHA1="583b82864b43cccde3be09cc00d2c8de14495356"
SP_TARBALL_URL="https://registry.npmjs.org/@screenpipe/cli-darwin-$SP_ARCH/-/cli-darwin-$SP_ARCH-$SP_VERSION.tgz"
echo "==> Using screenpipe v$SP_VERSION ($SP_ARCH) [pinned]"

mkdir -p "$CACHE_DIR"
TARBALL="$CACHE_DIR/screenpipe-$SP_VERSION-$SP_ARCH.tgz"
verify_tarball() {
    [ "$(shasum -a 1 "$1" | awk '{print $1}')" = "$SP_TARBALL_SHA1" ] \
        && tar -tzf "$1" >/dev/null 2>&1
}

if [ -f "$TARBALL" ] && ! verify_tarball "$TARBALL"; then
    echo "==> Cached screenpipe tarball is corrupt; downloading it again"
    rm -f "$TARBALL"
fi
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading screenpipe tarball"
    TARBALL_TMP="$TARBALL.part"
    rm -f "$TARBALL_TMP"
    curl -fsSL --retry 3 --retry-all-errors "$SP_TARBALL_URL" -o "$TARBALL_TMP"
    verify_tarball "$TARBALL_TMP"
    mv "$TARBALL_TMP" "$TARBALL"
fi

echo "==> Building $APP_NAME ($HOST_ARCH)"
swift build -c release --arch "$HOST_ARCH" --product "$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

cp ".build/$HOST_ARCH-apple-macosx/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
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

# Signing. Release builds pass MENGO_RELEASE=1 and MENGO_SIGN_IDENTITY with a
# "Developer ID Application" identity. Development builds prefer the stable
# local certificate so TCC grants survive, then fall back to ad-hoc signing.
CERT_NAME="Mengo Desktop Local Dev"
CERT_LINE=$(security find-identity -p basic login.keychain 2>/dev/null | grep "$CERT_NAME" || true)
if [ -z "$CERT_LINE" ]; then
    # Compatibility with development certificates created by older checkouts.
    CERT_NAME="ScreenpipeMenu Local Dev"
    CERT_LINE=$(security find-identity -p basic login.keychain 2>/dev/null | grep "$CERT_NAME" || true)
fi
CERT_SHA=$(echo "$CERT_LINE" | awk '{print $2}' | head -1)
if [ -n "${MENGO_SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$MENGO_SIGN_IDENTITY"
    echo "==> Codesigning with configured identity '$SIGN_IDENTITY'"
elif [ -n "$CERT_SHA" ]; then
    SIGN_IDENTITY="$CERT_SHA"
    echo "==> Codesigning with '$CERT_NAME' ($CERT_SHA)"
else
    SIGN_IDENTITY="-"
    echo "==> Codesigning ad-hoc (run ./bootstrap-cert.sh once for stable signing)"
fi

CODESIGN_EXTRA=()
if [ "${MENGO_RELEASE:-0}" = "1" ]; then
    if [ "$SIGN_IDENTITY" = "-" ] || ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
        echo "ERROR: MENGO_RELEASE=1 requires a valid Developer ID Application identity in MENGO_SIGN_IDENTITY."
        exit 1
    fi
    if [[ "$SIGN_IDENTITY" != *"Developer ID Application"* ]]; then
        echo "ERROR: release identity must be a Developer ID Application certificate."
        exit 1
    fi
    CODESIGN_EXTRA=(--options runtime --timestamp)
fi

# Sign from a temporary staging directory. iCloud/File Provider can immediately
# re-add FinderInfo to bundles assembled under Desktop, which makes codesign fail.
SIGN_STAGE=$(mktemp -d)
trap 'rm -rf "$SIGN_STAGE"' EXIT
SIGNED_APP="$SIGN_STAGE/$APP_NAME.app"
ditto --norsrc "$APP_BUNDLE" "$SIGNED_APP"
xattr -cr "$SIGNED_APP" 2>/dev/null || true

# Strip bundle-root extended attributes that nested codesigning can re-add.
strip_bundle_xattrs() {
    xattr -d com.apple.FinderInfo "$SIGNED_APP" 2>/dev/null || true
    xattr -d com.apple.provenance "$SIGNED_APP" 2>/dev/null || true
    xattr -d "com.apple.fileprovider.fpfs#P" "$SIGNED_APP" 2>/dev/null || true
}

codesign --remove-signature "$SIGNED_APP/Contents/Helpers/screenpipe" 2>/dev/null || true
codesign --sign "$SIGN_IDENTITY" --force "${CODESIGN_EXTRA[@]}" "$SIGNED_APP/Contents/Helpers/mlx.metallib"
codesign --sign "$SIGN_IDENTITY" --force "${CODESIGN_EXTRA[@]}" --identifier "$BUNDLE_ID" "$SIGNED_APP/Contents/Helpers/screenpipe"
strip_bundle_xattrs   # nested codesigns can re-add FinderInfo to the parent .app dir
codesign --sign "$SIGN_IDENTITY" --force "${CODESIGN_EXTRA[@]}" --identifier "$BUNDLE_ID" "$SIGNED_APP"
codesign --verify --deep --strict "$SIGNED_APP"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$SIGNED_APP" "$ZIP_OUT"

# A raw .app stored in this iCloud-synced checkout can receive FinderInfo after
# signing and become invalid. The verified ZIP is the canonical build artifact;
# install.sh extracts it directly into ~/Applications.
rm -rf "$APP_BUNDLE"
rm -rf "$SIGN_STAGE"
trap - EXIT

ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  screenpipe v$SP_VERSION ($SP_ARCH) embedded"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
