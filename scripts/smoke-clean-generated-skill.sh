#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SKILL_DIR="${MENGO_SKILL_SOURCE_DIR:-$HOME/.claude/skills/record-mengo-flow-skill}"
RUNTIME="${MENGO_SKILL_SMOKE_RUNTIME:-codex}"
RUN_MODEL="${MENGO_SKILL_SMOKE_RUN_MODEL:-1}"
INVOKE="${MENGO_SKILL_SMOKE_INVOKE:-1}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -d "$SOURCE_SKILL_DIR" ] || fail "source skill directory not found: $SOURCE_SKILL_DIR"
[ -s "$SOURCE_SKILL_DIR/SKILL.md" ] || fail "missing or empty source SKILL.md: $SOURCE_SKILL_DIR/SKILL.md"
[ -s "$SOURCE_SKILL_DIR/flow.json" ] || fail "missing or empty source flow.json: $SOURCE_SKILL_DIR/flow.json"

command -v ditto >/dev/null 2>&1 || fail "ditto is required"

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/mengo-clean-skill-home.XXXXXX")"
trap 'rm -rf "$TMP_HOME"' EXIT

SKILL_NAME="$(basename "$SOURCE_SKILL_DIR")"
CLEAN_SKILL_DIR="$TMP_HOME/.claude/skills/$SKILL_NAME"
mkdir -p "$(dirname "$CLEAN_SKILL_DIR")"

echo "==> Preparing clean generated-skill home"
ditto "$SOURCE_SKILL_DIR" "$CLEAN_SKILL_DIR"
echo "Source skill: $SOURCE_SKILL_DIR"
echo "Clean skill:  $CLEAN_SKILL_DIR"

echo
echo "==> Running generated-skill smoke from clean skill path"
MENGO_SKILL_DIR="$CLEAN_SKILL_DIR" \
MENGO_SKILL_SMOKE_RUNTIME="$RUNTIME" \
MENGO_SKILL_SMOKE_RUN_MODEL="$RUN_MODEL" \
MENGO_SKILL_SMOKE_INVOKE="$INVOKE" \
    "$ROOT/scripts/smoke-generated-skill.sh"

echo
echo "Clean generated-skill smoke passed."
