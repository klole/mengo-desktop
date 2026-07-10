#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MengoDesktop"
ZIP="$ROOT/$APP_NAME.zip"
CHECKSUM="$ROOT/$APP_NAME.zip.sha256"

: "${MENGO_SIGN_IDENTITY:?Set MENGO_SIGN_IDENTITY to your Developer ID Application identity}"
: "${MENGO_NOTARY_PROFILE:?Set MENGO_NOTARY_PROFILE to a notarytool keychain profile}"

case "$MENGO_SIGN_IDENTITY" in
    *"Developer ID Application"*) ;;
    *) echo "ERROR: MENGO_SIGN_IDENTITY must be a Developer ID Application identity."; exit 1 ;;
esac

echo "==> Building hardened-runtime release"
MENGO_RELEASE=1 MENGO_SIGN_IDENTITY="$MENGO_SIGN_IDENTITY" "$ROOT/build-mengo.sh"

echo "==> Submitting archive for Apple notarization"
xcrun notarytool submit "$ZIP" --keychain-profile "$MENGO_NOTARY_PROFILE" --wait

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto -x -k "$ZIP" "$STAGE"
STAGED_APP="$STAGE/$APP_NAME.app"

echo "==> Stapling and validating notarization ticket"
xcrun stapler staple "$STAGED_APP"
xcrun stapler validate "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
spctl --assess --type execute --verbose=2 "$STAGED_APP"

echo "==> Repacking stapled release"
STAPLED_ZIP="$STAGE/$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAPLED_ZIP"
mv "$STAPLED_ZIP" "$ZIP"

SHA256=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA256  $APP_NAME.zip" > "$CHECKSUM"

echo
echo "Release ready (not uploaded):"
echo "  $ZIP"
echo "  $CHECKSUM"
