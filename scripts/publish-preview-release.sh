#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-klole/mengo-desktop}"
RELEASE_TAG="${MENGO_RELEASE_TAG:-v0.1.0-preview}"
CONFIRM="${MENGO_PUBLISH_NON_NOTARIZED_PREVIEW:-0}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

cd "$ROOT"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required to publish the preview release"

if [ "$CONFIRM" != "1" ]; then
    cat >&2 <<EOF
ERROR: refusing to publish without explicit confirmation.

This preview is intentionally non-notarized unless a Developer ID build has
been produced separately. To publish the current draft prerelease, rerun with:

  MENGO_PUBLISH_NON_NOTARIZED_PREVIEW=1 $0

EOF
    exit 1
fi

echo "==> Verifying draft readiness"
"$ROOT/scripts/release-readiness-status.sh"

echo
echo "==> Publishing $RELEASE_TAG as a prerelease"
gh release edit "$RELEASE_TAG" \
    --repo "$REPO" \
    --draft=false \
    --prerelease=true \
    --notes-file "$ROOT/docs/release/v0.1.0-preview.md"

echo
echo "==> Verifying published prerelease"
MENGO_EXPECT_RELEASE_DRAFT=0 "$ROOT/scripts/release-readiness-status.sh"

echo
gh release view "$RELEASE_TAG" --repo "$REPO" --json tagName,isDraft,isPrerelease,url,assets
