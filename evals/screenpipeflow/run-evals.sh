#!/usr/bin/env bash
# Run synthesis evals against each fixture in fixtures/.
# Each fixture must contain manifest.json + expected.md.
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_DIR="$EVAL_DIR/fixtures"
PROMPT_FILE="$EVAL_DIR/../../Resources/synthesis-prompt.md"

if [ ! -f "$PROMPT_FILE" ]; then
    echo "ERROR: synthesis prompt not found at $PROMPT_FILE"
    exit 1
fi
PROMPT_BODY=$(cat "$PROMPT_FILE")

# Ensure we have everything to run claude -p.
if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude CLI not on PATH. Install from claude.ai/code."
    exit 1
fi

# Iterate over fixtures.
shopt -s nullglob
fixtures=("$FIXTURE_DIR"/*/)
if [ ${#fixtures[@]} -eq 0 ]; then
    echo "No fixtures in $FIXTURE_DIR — add some via the README."
    exit 0
fi

TOTAL=0
PASSED=0
for fixture in "${fixtures[@]}"; do
    name=$(basename "$fixture")
    TOTAL=$((TOTAL + 1))
    manifest="$fixture/manifest.json"
    expected="$fixture/expected.md"
    if [ ! -f "$manifest" ] || [ ! -f "$expected" ]; then
        echo "==> $name : SKIP (missing manifest.json or expected.md)"
        continue
    fi
    echo "==> $name"

    OUT_DIR=$(mktemp -d)
    PROMPT_FOR_FIXTURE="${PROMPT_BODY//\$MANIFEST_PATH/$manifest}"

    echo "    Running claude -p (this can take 30s–2min)…"
    claude -p "$PROMPT_FOR_FIXTURE" > "$OUT_DIR/out.txt" 2>&1 || true

    JUDGE_PROMPT="You are grading the output of a synthesis run against expected properties.
Reply with PASS or FAIL on the first line, followed by a one-line reason.

EXPECTED PROPERTIES:
$(cat "$expected")

ACTUAL SYNTHESIS LOG:
$(cat "$OUT_DIR/out.txt")"

    VERDICT=$(claude -p "$JUDGE_PROMPT" 2>/dev/null | head -1 || echo "FAIL judge error")
    echo "    $VERDICT"
    if [[ "$VERDICT" == PASS* ]]; then
        PASSED=$((PASSED + 1))
    fi
    rm -rf "$OUT_DIR"
done

echo
echo "==> $PASSED / $TOTAL passed"
[ "$PASSED" -eq "$TOTAL" ] || exit 1
