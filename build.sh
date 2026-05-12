#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenpipeMenu"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"
CACHE_DIR="$PROJECT_DIR/.build-cache"

cd "$PROJECT_DIR"

# Detect host arch — we bundle the matching screenpipe binary.
# (Apple Silicon Macs ship the arm64 build; Intel Macs ship x64.)
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    arm64) SP_ARCH="arm64" ;;
    x86_64) SP_ARCH="x64" ;;
    *) echo "unsupported arch: $HOST_ARCH"; exit 1 ;;
esac

echo "==> Resolving screenpipe latest version"
SP_VERSION=$(curl -fsSL https://registry.npmjs.org/screenpipe/latest \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
SP_TARBALL_URL="https://registry.npmjs.org/@screenpipe/cli-darwin-$SP_ARCH/-/cli-darwin-$SP_ARCH-$SP_VERSION.tgz"
echo "    version: $SP_VERSION"
echo "    arch:    $SP_ARCH"
echo "    url:     $SP_TARBALL_URL"

# Cache the tarball — re-running build shouldn't re-download 150 MB every time.
mkdir -p "$CACHE_DIR"
TARBALL="$CACHE_DIR/screenpipe-$SP_VERSION-$SP_ARCH.tgz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading screenpipe tarball"
    curl -fsSL "$SP_TARBALL_URL" -o "$TARBALL"
fi

echo "==> Building ScreenpipeMenu (universal)"
swift build -c release --arch arm64 --arch x86_64

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Embed the screenpipe binary + its Metal library inside the bundle.
# Tarball layout: package/bin/{screenpipe, mlx.metallib}
# --strip-components=2 drops "package/bin/" so files land directly in Helpers/.
tar -xzf "$TARBALL" -C "$APP_BUNDLE/Contents/Helpers" --strip-components=2 package/bin/
chmod +x "$APP_BUNDLE/Contents/Helpers/screenpipe"

echo "==> Ad-hoc codesigning"
# Sign nested items first (mlx.metallib + screenpipe helper), then the outer .app.
# The helper gets the SAME identifier as the .app so macOS TCC treats them as one code
# identity — the spawned child then inherits ScreenpipeMenu's Screen Recording grant.
codesign --remove-signature "$APP_BUNDLE/Contents/Helpers/screenpipe" 2>/dev/null || true
codesign --sign - --force "$APP_BUNDLE/Contents/Helpers/mlx.metallib"
codesign --sign - --force --identifier com.mengo.screenpipemenu \
    "$APP_BUNDLE/Contents/Helpers/screenpipe"
codesign --sign - --force --identifier com.mengo.screenpipemenu "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  screenpipe v$SP_VERSION ($SP_ARCH) embedded"
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
