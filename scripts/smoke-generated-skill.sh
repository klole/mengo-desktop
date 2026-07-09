#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${MENGO_SKILL_SMOKE_RUNTIME:-codex}"
SKILL_DIR="${MENGO_SKILL_DIR:-$HOME/.claude/skills/record-mengo-flow-skill}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

echo "==> Generated skill structure"
[ -d "$SKILL_DIR" ] || fail "skill directory not found: $SKILL_DIR"
[ -s "$SKILL_DIR/SKILL.md" ] || fail "missing or empty SKILL.md in $SKILL_DIR"
[ -s "$SKILL_DIR/flow.json" ] || fail "missing or empty flow.json in $SKILL_DIR"

if command -v jq >/dev/null 2>&1; then
    jq empty "$SKILL_DIR/flow.json" >/dev/null || fail "flow.json is not valid JSON"
else
    python3 -m json.tool "$SKILL_DIR/flow.json" >/dev/null || fail "flow.json is not valid JSON"
fi

if [ -d "$SKILL_DIR/frames" ]; then
    FRAME_COUNT="$(find "$SKILL_DIR/frames" -type f | wc -l | tr -d ' ')"
else
    FRAME_COUNT=0
fi

echo "Skill: $SKILL_DIR"
echo "Frames: $FRAME_COUNT"

if ! grep -Eiq '^name:|^#|^##' "$SKILL_DIR/SKILL.md"; then
    fail "SKILL.md does not look like a readable skill document"
fi

if [ "${MENGO_SKILL_SMOKE_RUN_MODEL:-0}" != "1" ]; then
    echo
    echo "Generated skill file smoke passed."
    echo "Set MENGO_SKILL_SMOKE_RUN_MODEL=1 to have $RUNTIME read the skill."
    exit 0
fi

LAST_MESSAGE="$(mktemp "${TMPDIR:-/tmp}/mengo-skill-smoke.XXXXXX")"
trap 'rm -f "$LAST_MESSAGE"' EXIT

case "$RUNTIME" in
  codex)
    CODEX_BIN="${CODEX_BIN:-codex}"
    echo
    echo "==> Codex generated-skill read smoke"
    "$CODEX_BIN" exec \
        --dangerously-bypass-approvals-and-sandbox \
        --skip-git-repo-check \
        --add-dir "$SKILL_DIR" \
        --output-last-message "$LAST_MESSAGE" \
        "Read $SKILL_DIR/SKILL.md and $SKILL_DIR/flow.json. Do not modify files or call tools. Reply with exactly this JSON object shape and no markdown: {\"status\":\"ok\",\"skillDir\":\"$SKILL_DIR\",\"readSkill\":true,\"readFlow\":true}" \
        >/tmp/mengo-generated-skill-smoke.stdout \
        2>/tmp/mengo-generated-skill-smoke.stderr

    [ -s "$LAST_MESSAGE" ] || {
        echo "stderr:"
        sed -n '1,120p' /tmp/mengo-generated-skill-smoke.stderr
        fail "Codex did not write the last-message file"
    }
    cat "$LAST_MESSAGE"
    echo
    if ! grep -F '"status"' "$LAST_MESSAGE" | grep -F '"ok"' >/dev/null; then
        fail "Codex generated-skill read smoke did not return status ok"
    fi
    echo "Codex generated-skill read smoke passed."
    ;;
  *)
    fail "unsupported MENGO_SKILL_SMOKE_RUNTIME=$RUNTIME; currently supported: codex"
    ;;
esac
