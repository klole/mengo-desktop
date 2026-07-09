#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MengoDesktop"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
HOST_ARCH="$(uname -m)"
ZIP_OUT="$PROJECT_DIR/$APP_NAME-macos-$HOST_ARCH.zip"
NOTARY_PROFILE="${MENGO_NOTARY_PROFILE:-mengo-notary}"
SIGNING_IDENTITY="${MENGO_SIGNING_IDENTITY:-Developer ID Application}"
CHECK_ONLY=0

usage() {
    cat <<EOF
Usage: scripts/notarize-mengo.sh [--check]

Build, notarize, staple, re-zip, and verify MengoDesktop.app.

Environment:
  MENGO_SIGNING_IDENTITY  Developer ID Application identity name or SHA.
                          Default: Developer ID Application
  MENGO_NOTARY_PROFILE    notarytool keychain profile.
                          Default: mengo-notary

Examples:
  scripts/notarize-mengo.sh --check
  MENGO_SIGNING_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \\
  MENGO_NOTARY_PROFILE=mengo-notary \\
    scripts/notarize-mengo.sh
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

cd "$PROJECT_DIR"

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

for cmd in security xcrun codesign ditto spctl shasum; do
    require_command "$cmd"
done

verify_developer_id_runtime_signature() {
    local target="$1"
    local label="$2"
    local details
    codesign --verify --deep --strict --verbose=2 "$target"
    details="$(codesign -dv "$target" 2>&1)"
    echo "$details"
    echo "$details" | grep -F "Authority=Developer ID Application" >/dev/null || {
        echo "ERROR: $label is not signed with a Developer ID Application authority" >&2
        exit 1
    }
    echo "$details" | grep -F "Runtime Version=" >/dev/null || {
        echo "ERROR: $label is not signed with hardened runtime" >&2
        exit 1
    }
}

echo "==> Checking Developer ID signing identity"
IDENTITIES="$(security find-identity -v -p codesigning || true)"
echo "$IDENTITIES"
SIGNING_OK=1
if ! echo "$IDENTITIES" | grep -F "$SIGNING_IDENTITY" >/dev/null; then
    SIGNING_OK=0
    echo "ERROR: Developer ID signing identity not found: $SIGNING_IDENTITY"
    echo "Install a Developer ID Application certificate or set MENGO_SIGNING_IDENTITY."
fi

echo
echo "==> Checking notarytool profile"
NOTARY_OK=1
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARY_OK=0
    echo "ERROR: notarytool keychain profile is not usable: $NOTARY_PROFILE"
    echo "Create it with:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id <team-id>"
    echo "Or set MENGO_NOTARY_PROFILE to an existing profile."
else
    echo "notarytool profile is usable: $NOTARY_PROFILE"
fi

if [ "$SIGNING_OK" -ne 1 ] || [ "$NOTARY_OK" -ne 1 ]; then
    exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo
    echo "Notarization preflight passed."
    exit 0
fi

echo "==> Building Developer ID signed artifact"
MENGO_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
MENGO_SIGN_FOR_NOTARIZATION=1 \
    ./build-mengo.sh

echo "==> Verifying Developer ID signature"
verify_developer_id_runtime_signature "$APP_BUNDLE" "$APP_NAME.app"
verify_developer_id_runtime_signature "$APP_BUNDLE/Contents/Helpers/screenpipe" "screenpipe helper"

echo "==> Submitting to Apple notarization"
xcrun notarytool submit "$ZIP_OUT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "==> Re-zipping stapled app"
rm -f "$ZIP_OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

ZIP_SHA="$(shasum -a 256 "$ZIP_OUT" | awk '{print $1}')"
echo "Notarized zip sha256: $ZIP_SHA"

echo "==> Verifying re-zipped notarized artifact"
TMP_VERIFY="$(mktemp -d "${TMPDIR:-/tmp}/mengo-notarized-verify.XXXXXX")"
trap 'rm -rf "$TMP_VERIFY"' EXIT
ditto -x -k "$ZIP_OUT" "$TMP_VERIFY"
EXTRACTED_APP="$TMP_VERIFY/$APP_NAME.app"
[ -d "$EXTRACTED_APP" ] || {
    echo "ERROR: extracted notarized app not found: $EXTRACTED_APP" >&2
    exit 1
}
verify_developer_id_runtime_signature "$EXTRACTED_APP" "extracted $APP_NAME.app"
xcrun stapler validate "$EXTRACTED_APP"
spctl --assess --type execute -vv "$EXTRACTED_APP"

echo "==> Gatekeeper assessment"
spctl --assess --type execute -vv "$APP_BUNDLE"

echo
echo "Done."
echo "  Notarized app: $APP_BUNDLE"
echo "  Notarized zip: $ZIP_OUT"
echo "  SHA-256: $ZIP_SHA"
