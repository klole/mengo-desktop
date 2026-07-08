#!/usr/bin/env bash
set -euo pipefail

CODEX_BIN="${CODEX_BIN:-codex}"

echo "==> Codex version"
"$CODEX_BIN" --version

echo "==> Codex MCP setup"
MCP_LIST="$("$CODEX_BIN" mcp list)"
echo "$MCP_LIST"
if ! echo "$MCP_LIST" | grep -i "screenpipe" >/dev/null; then
    echo "ERROR: Codex MCP list does not include screenpipe."
    echo "Run: codex mcp add screenpipe -- npx -y screenpipe-mcp"
    exit 1
fi

if [ "${MENGO_CODEX_SMOKE_RUN_MODEL:-0}" != "1" ]; then
    echo
    echo "Codex CLI and screenpipe MCP preflight passed."
    echo "Set MENGO_CODEX_SMOKE_RUN_MODEL=1 to verify Codex exec --output-last-message behavior."
    exit 0
fi

TMPDIR_SMOKE="$(mktemp -d)"
LAST_MESSAGE="$TMPDIR_SMOKE/last-message.txt"

echo "==> Codex exec final-message file"
"$CODEX_BIN" exec \
    --dangerously-bypass-approvals-and-sandbox \
    --skip-git-repo-check \
    --add-dir "$TMPDIR_SMOKE" \
    --output-last-message "$LAST_MESSAGE" \
    "Do not call tools. Reply with exactly this single JSON line: {\"status\":\"ok\",\"outputDir\":\"$TMPDIR_SMOKE\",\"slug\":\"codex-runtime-smoke\"}" \
    >/tmp/mengo-codex-smoke.stdout \
    2>/tmp/mengo-codex-smoke.stderr

if [ ! -s "$LAST_MESSAGE" ]; then
    echo "ERROR: Codex did not write the last-message file: $LAST_MESSAGE"
    echo "stderr:"
    sed -n '1,120p' /tmp/mengo-codex-smoke.stderr
    exit 1
fi

cat "$LAST_MESSAGE"
echo
echo "Codex exec final-message smoke passed."
