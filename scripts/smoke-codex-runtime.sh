#!/usr/bin/env bash
set -euo pipefail

CODEX_BIN="${CODEX_BIN:-codex}"

if [ "${MENGO_CODEX_SMOKE_NEGATIVE:-}" = "missing-mcp" ]; then
    TMPDIR_NEGATIVE="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR_NEGATIVE"' EXIT
    FAKE_CODEX="$TMPDIR_NEGATIVE/codex"
    cat >"$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo "codex-cli fake-negative"
    ;;
  mcp)
    if [ "${2:-}" = "list" ]; then
      echo "No MCP servers configured."
    else
      echo "unexpected fake codex mcp command" >&2
      exit 64
    fi
    ;;
  *)
    echo "unexpected fake codex command" >&2
    exit 64
    ;;
esac
EOF
    chmod +x "$FAKE_CODEX"
    set +e
    OUTPUT="$(CODEX_BIN="$FAKE_CODEX" MENGO_CODEX_SMOKE_NEGATIVE= "$0" 2>&1)"
    STATUS=$?
    set -e
    echo "$OUTPUT"
    if [ "$STATUS" -eq 0 ]; then
        echo "ERROR: negative Codex smoke unexpectedly passed."
        exit 1
    fi
    if ! echo "$OUTPUT" | grep -F "ERROR: Codex MCP list does not include screenpipe." >/dev/null; then
        echo "ERROR: negative Codex smoke did not report missing screenpipe MCP."
        exit 1
    fi
    if ! echo "$OUTPUT" | grep -F "Run: codex mcp add screenpipe -- npx -y screenpipe-mcp" >/dev/null; then
        echo "ERROR: negative Codex smoke did not print the setup command."
        exit 1
    fi
    echo
    echo "Negative Codex MCP smoke passed."
    exit 0
fi

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
