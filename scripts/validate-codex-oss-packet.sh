#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-klole/mengo-desktop}"
PR_NUMBER="${MENGO_RELEASE_PR:-8}"
RELEASE_TAG="${MENGO_RELEASE_TAG:-v0.1.0-preview}"
PACKET="${MENGO_CODEX_OSS_PACKET:-$ROOT/docs/release/codex-for-oss-submission-packet.md}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
[ -f "$PACKET" ] || fail "packet not found: $PACKET"

REPO_JSON="$(gh repo view "$REPO" --json isPrivate,stargazerCount,forkCount,pullRequests,url)"
PR_JSON="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json number,isDraft,mergeStateStatus,statusCheckRollup,url)"
RELEASE_JSON="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json tagName,isDraft,isPrerelease,url,assets)"
ISSUES_JSON="$(gh issue list --repo "$REPO" --state open --json number,title,url --limit 100)"

export PACKET REPO_JSON PR_JSON RELEASE_JSON ISSUES_JSON
python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

packet_path = Path(os.environ["PACKET"])
packet = packet_path.read_text(encoding="utf-8")
repo = json.loads(os.environ["REPO_JSON"])
pr = json.loads(os.environ["PR_JSON"])
release = json.loads(os.environ["RELEASE_JSON"])
issues = json.loads(os.environ["ISSUES_JSON"])

errors: list[str] = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def section_text(title: str) -> str:
    pattern = rf"## {re.escape(title)}\n(?P<body>.*?)(?=\n## |\Z)"
    match = re.search(pattern, packet, re.S)
    if not match:
        errors.append(f"missing section: {title}")
        return ""
    return match.group("body")

def answer_block(title: str) -> tuple[str, int | None]:
    body = section_text(title)
    count_match = re.search(r"Character count:\s*(\d+)\.", body)
    declared = int(count_match.group(1)) if count_match else None
    if declared is None:
        errors.append(f"{title}: missing declared character count")
    block_match = re.search(r"```text\n(?P<text>.*?)\n```", body, re.S)
    if not block_match:
        errors.append(f"{title}: missing text code block")
        return "", declared
    return block_match.group("text"), declared

for title in ("Why This Repository Qualifies", "API Credit Usage", "Anything Else"):
    text, declared = answer_block(title)
    actual = len(text)
    require(actual <= 500, f"{title}: {actual} characters exceeds 500")
    if declared is not None:
        require(declared == actual, f"{title}: declared count {declared} != actual {actual}")

visibility = "private" if repo.get("isPrivate") else "public"
asset = (release.get("assets") or [{}])[0]
open_prs = repo.get("pullRequests", {}).get("totalCount")
ci_checks = pr.get("statusCheckRollup") or []
successful_check_names = [check.get("name") for check in ci_checks if check.get("conclusion") == "SUCCESS"]
ci_summary = ", ".join(successful_check_names) if successful_check_names else "no successful checks reported"
pr_state = "draft PR" if pr.get("isDraft") else "PR"
release_state = "draft" if release.get("isDraft") else "published"
release_kind = "prerelease" if release.get("isPrerelease") else "release"

expected_lines = [
    f"- Repository visibility: {visibility}.",
    f"- Stars: {repo.get('stargazerCount')}.",
    f"- Forks: {repo.get('forkCount')}.",
    f"- Open issues: {len(issues)}.",
    f"- Open PRs: {open_prs}, {pr_state} #{pr.get('number')}.",
    f"- CI: macOS `{ci_summary}` passing on PR #{pr.get('number')}.",
    f"- Release: `{release.get('tagName')}`, {release_state} {release_kind}.",
    f"- Release URL: `{release.get('url')}`.",
    f"- Release asset: `{asset.get('name')}`.",
    f"- Release asset digest: `{asset.get('digest')}`.",
    f"- Release downloads: {asset.get('downloadCount')}.",
]

for line in expected_lines:
    require(line in packet, f"missing or stale packet fact: {line}")

do_not_claim_downloads = (
    f"- Do not claim broad adoption; current metrics are {repo.get('stargazerCount')} stars, "
    f"{repo.get('forkCount')} forks, and {asset.get('downloadCount')} release downloads."
)
require(do_not_claim_downloads in packet, f"missing or stale Do Not Claim downloads line: {do_not_claim_downloads}")

require("OpenAI Organization ID: fill manually" in packet, "packet must keep OpenAI Organization ID as a manual field")
require("Do not claim notarization" in packet, "packet must warn against claiming notarization")

if errors:
    print("Codex OSS packet validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Codex OSS packet validation passed.")
print(f"Packet: {packet_path}")
print(f"Live metrics: {repo.get('stargazerCount')} stars, {repo.get('forkCount')} forks, {len(issues)} open issues, {asset.get('downloadCount')} preview downloads.")
PY
