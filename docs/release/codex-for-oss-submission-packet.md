# Codex for OSS Submission Packet

Last refreshed: 2026-07-09.

Use this as the copy source immediately before submitting the OpenAI Codex for Open Source form. Refresh metrics first:

```bash
scripts/codex-oss-application-status.sh
scripts/validate-codex-oss-packet.sh
```

## Form Fields

- First name: fill manually.
- Last name: fill manually.
- Email: use the email associated with the ChatGPT account.
- GitHub username: `klole`.
- GitHub repository URL: `https://github.com/klole/mengo-desktop`.
- Maintainer role: `Primary maintainer`.
- Interested in: `API credits for my project`.
- OpenAI Organization ID: fill manually from OpenAI platform organization settings.

## Current Public Facts

- Repository visibility: public.
- Stars: 0.
- Forks: 0.
- Open issues: 3.
- Open PRs: 1, draft PR #8.
- CI: macOS `build-test` passing on PR #8.
- Release: `v0.1.0-preview`, published prerelease.
- Release URL: `https://github.com/klole/mengo-desktop/releases/tag/v0.1.0-preview`.
- Release asset: `MengoDesktop-macos-arm64.zip`.
- Release asset digest: `sha256:2fc1238cc83c94cf79ce7b0e5732e587676e58e0b0d4b39a529f7c427a970327`.
- Release downloads: 0.
- Notarization: not complete; the preview is explicitly non-notarized.

## Why This Repository Qualifies

Character count: 305.

```text
Mengo Desktop is an open-source macOS app for local AI memory and repeatable workflow capture. It turns maintainer workflows into reusable Codex/Claude-style skills, with public docs, CI, issue triage, release notes, and a V1 preview pipeline. It is early, but directly targets OSS maintenance automation.
```

## API Credit Usage

Character count: 305.

```text
I would use API credits for maintainer automation: PR review, release checklist generation, security-oriented review, docs maintenance, and evaluating Mengo's skill synthesis loop. Credits would also test Codex workflows that convert real maintainer actions into reusable skills for this open-source repo.
```

## Anything Else

Character count: 316.

```text
The repo is early but active: PR #8 prepares a clean V1 preview with MIT license, security/contributing docs, macOS CI, local preview mode, Codex runtime smoke scripts, and a published preview artifact. Current public metrics are small, so the case is ecosystem relevance and active maintenance rather than adoption.
```

## Evidence To Cite If Needed

- Published preview release: `https://github.com/klole/mengo-desktop/releases/tag/v0.1.0-preview`.
- Readiness PR: `https://github.com/klole/mengo-desktop/pull/8`.
- Release readiness command: `MENGO_SKILL_SMOKE_RUN_MODEL=1 MENGO_SKILL_SMOKE_INVOKE=1 scripts/release-readiness-status.sh`.
- Application status command: `scripts/codex-oss-application-status.sh`.
- Manual smoke checklist: `docs/manual-smoke-tests/mengo-v1.md`.

## Do Not Claim

- Do not claim broad adoption; current metrics are 0 stars, 0 forks, and 0 release downloads.
- Do not claim notarization; the current preview is explicitly non-notarized.
- Do not claim Codex is the default runtime until the in-app broken-runtime GUI alert and clean-user manual matrix pass.
- Do not claim Intel artifact support until an Intel-built artifact is smoke-tested.
