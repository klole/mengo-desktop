#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/MengoDesktop.app"
ZIP="$ROOT/MengoDesktop-macos-arm64.zip"
RELEASE_NOTES="$ROOT/docs/release/v0.1.0-preview.md"
REPO="${GITHUB_REPOSITORY:-klole/mengo-desktop}"
PR_NUMBER="${MENGO_RELEASE_PR:-8}"
RELEASE_TAG="${MENGO_RELEASE_TAG:-v0.1.0-preview}"
EXPECT_RELEASE_DRAFT="${MENGO_EXPECT_RELEASE_DRAFT:-1}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    echo "PASS: $*"
}

echo "==> Git state"
cd "$ROOT"
BRANCH="$(git branch --show-current)"
STATUS="$(git status --short)"
if [ -n "$STATUS" ]; then
    echo "$STATUS"
    fail "working tree is not clean"
fi
pass "working tree clean on $BRANCH"

echo
echo "==> Tests"
swift test
pass "swift test"

echo
echo "==> Local artifact"
[ -d "$APP" ] || fail "missing app bundle: $APP"
[ -f "$ZIP" ] || fail "missing zip: $ZIP"
codesign --verify --deep --strict --verbose=2 "$APP"
pass "codesign verification"

LOCAL_SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
NOTES_SHA="$(grep -Eo '^[0-9a-f]{64}  MengoDesktop-macos-arm64.zip$' "$RELEASE_NOTES" | awk '{print $1}' | tail -1)"
[ -n "$NOTES_SHA" ] || fail "could not find release-notes checksum"
if [ "$LOCAL_SHA" != "$NOTES_SHA" ]; then
    fail "local zip checksum $LOCAL_SHA does not match release notes $NOTES_SHA"
fi
pass "local zip checksum matches release notes: $LOCAL_SHA"

if spctl --assess --type execute -vv "$APP" >/tmp/mengo-spctl.out 2>&1; then
    pass "Gatekeeper assessment passed"
else
    cat /tmp/mengo-spctl.out
    if grep -qi "not notarized" "$RELEASE_NOTES" && grep -qi "rejected" /tmp/mengo-spctl.out; then
        pass "Gatekeeper rejection is documented for non-notarized preview"
    else
        fail "Gatekeeper rejected app and release notes do not document expected non-notarized preview"
    fi
fi

echo
echo "==> Codex runtime smoke"
"$ROOT/scripts/smoke-codex-runtime.sh"
MENGO_CODEX_SMOKE_NEGATIVE=missing-mcp "$ROOT/scripts/smoke-codex-runtime.sh"
if [ "${MENGO_CODEX_SMOKE_RUN_MODEL:-0}" = "1" ]; then
    MENGO_CODEX_SMOKE_RUN_MODEL=1 "$ROOT/scripts/smoke-codex-runtime.sh"
else
    echo "SKIP: set MENGO_CODEX_SMOKE_RUN_MODEL=1 to run Codex model final-message smoke"
fi
pass "Codex scripted smoke"

echo
echo "==> Generated skill smoke"
"$ROOT/scripts/smoke-generated-skill.sh"
if [ "${MENGO_SKILL_SMOKE_RUN_MODEL:-0}" = "1" ]; then
    MENGO_SKILL_SMOKE_RUN_MODEL=1 "$ROOT/scripts/smoke-generated-skill.sh"
else
    echo "SKIP: set MENGO_SKILL_SMOKE_RUN_MODEL=1 to have Codex read the generated skill"
fi
pass "Generated skill smoke"

echo
echo "==> Notarization preflight"
if "$ROOT/scripts/notarize-mengo.sh" --check; then
    pass "notarization preflight"
else
    echo "WARN: notarization preflight is not complete; non-notarized preview path must remain explicit"
fi

if command -v gh >/dev/null 2>&1; then
    echo
    if [ "$EXPECT_RELEASE_DRAFT" = "1" ]; then
        echo "==> GitHub PR and draft release"
    else
        echo "==> GitHub PR and published release"
    fi
    PR_STATE="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json headRefOid,mergeStateStatus,statusCheckRollup)"
    echo "$PR_STATE"
    if ! echo "$PR_STATE" | grep -q '"mergeStateStatus":"CLEAN"'; then
        fail "PR #$PR_NUMBER is not clean"
    fi
    if ! echo "$PR_STATE" | grep -q '"conclusion":"SUCCESS"'; then
        fail "PR #$PR_NUMBER does not have a successful check rollup"
    fi
    pass "PR #$PR_NUMBER clean with successful checks"

    RELEASE_STATE="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json isDraft,isPrerelease,assets,url)"
    echo "$RELEASE_STATE"
    if [ "$EXPECT_RELEASE_DRAFT" = "1" ]; then
        if ! echo "$RELEASE_STATE" | grep -q '"isDraft":true'; then
            fail "release $RELEASE_TAG is not draft"
        fi
    else
        if ! echo "$RELEASE_STATE" | grep -q '"isDraft":false'; then
            fail "release $RELEASE_TAG is still draft"
        fi
    fi
    if ! echo "$RELEASE_STATE" | grep -q '"isPrerelease":true'; then
        fail "release $RELEASE_TAG is not marked prerelease"
    fi
    if ! echo "$RELEASE_STATE" | grep -q "\"digest\":\"sha256:$LOCAL_SHA\""; then
        fail "release asset digest does not match local checksum $LOCAL_SHA"
    fi
    pass "release asset digest matches local checksum"
else
    echo "SKIP: gh not installed; GitHub PR/release checks not run"
fi

cat <<'EOF'

Remaining manual/external gates:
- Clean-user GUI smoke matrix.
- In-app broken-Codex/MCP GUI alert smoke.
- Full generated-skill invocation from the selected runtime.
- Developer ID signing/notarization, or explicit non-notarized preview publish decision.
- Publish release and fill final Codex for OSS application metrics.
EOF
