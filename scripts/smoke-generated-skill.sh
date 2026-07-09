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
    echo "Set MENGO_SKILL_SMOKE_INVOKE=1 too to have $RUNTIME apply the skill instructions."
    exit 0
fi

LAST_MESSAGE="$(mktemp "${TMPDIR:-/tmp}/mengo-skill-smoke.XXXXXX")"
trap 'rm -f "$LAST_MESSAGE"' EXIT

case "$RUNTIME" in
  codex)
    CODEX_BIN="${CODEX_BIN:-codex}"
    echo
    if [ "${MENGO_SKILL_SMOKE_INVOKE:-0}" = "1" ]; then
        echo "==> Codex generated-skill invocation smoke"
        PROMPT="Read $SKILL_DIR/SKILL.md and $SKILL_DIR/flow.json using read-only file inspection as needed. Do not modify files. Invoke the generated skill for task_to_record=\"record a short Mengo Flow task\" and output_skills_dir=\"$SKILL_DIR\". Reply with exactly this JSON object shape and no markdown: {\"status\":\"ok\",\"skillDir\":\"$SKILL_DIR\",\"readSkill\":true,\"readFlow\":true,\"invoked\":true,\"stepCount\":5}"
    else
        echo "==> Codex generated-skill read smoke"
        PROMPT="Read $SKILL_DIR/SKILL.md and $SKILL_DIR/flow.json using read-only file inspection as needed. Do not modify files. Reply with exactly this JSON object shape and no markdown: {\"status\":\"ok\",\"skillDir\":\"$SKILL_DIR\",\"readSkill\":true,\"readFlow\":true}"
    fi
    "$CODEX_BIN" exec \
        --dangerously-bypass-approvals-and-sandbox \
        --skip-git-repo-check \
        --add-dir "$SKILL_DIR" \
        --output-last-message "$LAST_MESSAGE" \
        "$PROMPT" \
        >/tmp/mengo-generated-skill-smoke.stdout \
        2>/tmp/mengo-generated-skill-smoke.stderr

    [ -s "$LAST_MESSAGE" ] || {
        echo "stderr:"
        sed -n '1,120p' /tmp/mengo-generated-skill-smoke.stderr
        fail "Codex did not write the last-message file"
    }
    cat "$LAST_MESSAGE"
    echo
    python3 - "$LAST_MESSAGE" <<'PY' || fail "Codex generated-skill smoke did not return the expected JSON"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

required = {
    "status": "ok",
    "readSkill": True,
    "readFlow": True,
}
for key, value in required.items():
    if data.get(key) != value:
        raise SystemExit(f"{key} mismatch")
PY
    if [ "${MENGO_SKILL_SMOKE_INVOKE:-0}" = "1" ]; then
        python3 - "$LAST_MESSAGE" <<'PY' || fail "Codex generated-skill invocation smoke did not return invoked true"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

if data.get("invoked") is not True:
    raise SystemExit("invoked mismatch")
PY
        echo "Codex generated-skill invocation smoke passed."
    else
        echo "Codex generated-skill read smoke passed."
    fi
    ;;
  *)
    fail "unsupported MENGO_SKILL_SMOKE_RUNTIME=$RUNTIME; currently supported: codex"
    ;;
esac
