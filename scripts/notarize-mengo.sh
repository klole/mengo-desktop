#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MengoDesktop"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
HOST_ARCH="$(uname -m)"
ZIP_OUT="$PROJECT_DIR/$APP_NAME-macos-$HOST_ARCH.zip"
NOTARY_PROFILE="${MENGO_NOTARY_PROFILE:-mengo-notary}"
SIGNING_IDENTITY="${MENGO_SIGNING_IDENTITY:-Developer ID Application}"

cd "$PROJECT_DIR"

if ! security find-identity -v -p codesigning | grep -F "$SIGNING_IDENTITY" >/dev/null; then
    echo "ERROR: Developer ID signing identity not found: $SIGNING_IDENTITY"
    echo "Install a Developer ID Application certificate or set MENGO_SIGNING_IDENTITY."
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "ERROR: notarytool keychain profile is not usable: $NOTARY_PROFILE"
    echo "Create it with:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id <team-id>"
    echo "Or set MENGO_NOTARY_PROFILE to an existing profile."
    exit 1
fi

echo "==> Building Developer ID signed artifact"
MENGO_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
MENGO_SIGN_FOR_NOTARIZATION=1 \
    ./build-mengo.sh

echo "==> Verifying Developer ID signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "Authority=Developer ID Application|Runtime Version" >/dev/null

echo "==> Submitting to Apple notarization"
xcrun notarytool submit "$ZIP_OUT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "==> Re-zipping stapled app"
rm -f "$ZIP_OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

echo "==> Gatekeeper assessment"
spctl --assess --type execute -vv "$APP_BUNDLE"

echo
echo "Done."
echo "  Notarized app: $APP_BUNDLE"
echo "  Notarized zip: $ZIP_OUT"
