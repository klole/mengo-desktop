#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-klole/mengo-desktop}"
PR_NUMBER="${MENGO_RELEASE_PR:-8}"
RELEASE_TAG="${MENGO_RELEASE_TAG:-v0.1.0-preview}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"

REPO_JSON="$(gh repo view "$REPO" --json nameWithOwner,isPrivate,stargazerCount,forkCount,issues,pullRequests,url)"
PR_JSON="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json number,isDraft,mergeStateStatus,statusCheckRollup,url)"
RELEASE_JSON="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json tagName,isDraft,isPrerelease,url,assets)"
ISSUES_JSON="$(gh issue list --repo "$REPO" --state open --json number,title,url --limit 100)"

export REPO_JSON PR_JSON RELEASE_JSON ISSUES_JSON
python3 - <<'PY'
import json
import os

repo = json.loads(os.environ["REPO_JSON"])
pr = json.loads(os.environ["PR_JSON"])
release = json.loads(os.environ["RELEASE_JSON"])
issues = json.loads(os.environ["ISSUES_JSON"])

assets = release.get("assets") or []
asset = assets[0] if assets else {}
checks = pr.get("statusCheckRollup") or []
successful_checks = [
    check.get("name")
    for check in checks
    if check.get("conclusion") == "SUCCESS"
]

repo_visibility = "private" if repo.get("isPrivate") else "public"
release_state = "draft" if release.get("isDraft") else "published"
release_kind = "prerelease" if release.get("isPrerelease") else "release"
pr_state = "draft PR" if pr.get("isDraft") else "PR"
ci_summary = ", ".join(successful_checks) if successful_checks else "no successful checks reported"

print("# Codex for OSS Application Status")
print()
print("Refresh this immediately before submitting the Codex for OSS application.")
print()
print("## Current Facts")
print()
print(f"- Repository: {repo_visibility}.")
print(f"- Repository URL: `{repo.get('url')}`.")
print(f"- Stars: {repo.get('stargazerCount')}.")
print(f"- Forks: {repo.get('forkCount')}.")
print(f"- Open issues: {len(issues)}.")
print(f"- Open PRs: {repo.get('pullRequests', {}).get('totalCount')}.")
print(f"- Release PR: {pr_state} #{pr.get('number')}, `{pr.get('mergeStateStatus')}`, {pr.get('url')}.")
print(f"- CI: {ci_summary}.")
print(f"- Preview release: `{release.get('tagName')}`, {release_state} {release_kind}, {release.get('url')}.")
if asset:
    print(f"- Preview asset: `{asset.get('name')}`.")
    print(f"- Preview asset digest: `{asset.get('digest')}`.")
    print(f"- Preview asset downloads: {asset.get('downloadCount')}.")
else:
    print("- Preview asset: none found.")
print()
print("## Open Issues")
print()
for issue in issues:
    print(f"- #{issue.get('number')}: {issue.get('title')} ({issue.get('url')})")
print()
print("## Submission Reminders")
print()
print("- Do not claim broad adoption unless stars/forks/downloads support it.")
print("- Do not claim notarization until Gatekeeper passes on a notarized build.")
print("- If publishing the non-notarized preview, verify it with `MENGO_EXPECT_RELEASE_DRAFT=0 scripts/release-readiness-status.sh` first.")
print("- Fill OpenAI Organization ID manually from OpenAI platform settings.")
PY
