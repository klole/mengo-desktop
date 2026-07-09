# Codex for OSS Application Notes

Use this after the preview release is published and final metrics are refreshed. The Codex for OSS form asks for these fields and limits the three narrative answers to 500 characters.

Refresh the GitHub facts immediately before submitting:

```bash
scripts/codex-oss-application-status.sh
```

## Copy-Ready Fields

- GitHub username: `klole`
- GitHub repository URL: `https://github.com/klole/mengo-desktop`
- Maintainer role: `Primary maintainer`
- Interested in: `API credits for my project`; optionally also `Codex Security` after security review scope is clear.
- OpenAI Organization ID: fill from the OpenAI platform org settings before submitting.

## Why This Repository Qualifies

```text
Mengo Desktop is an open-source macOS app for local AI memory and repeatable workflow capture. It turns maintainer workflows into reusable Codex/Claude-style skills, with public docs, CI, issue triage, release notes, and a V1 preview pipeline. It is early, but directly targets OSS maintenance automation.
```

Character count: 305.

## API Credit Usage

```text
I would use API credits for maintainer automation: PR review, release checklist generation, security-oriented review, docs maintenance, and evaluating Mengo's skill synthesis loop. Credits would also test Codex workflows that convert real maintainer actions into reusable skills for this open-source repo.
```

Character count: 305.

## Anything Else

```text
The repo is early but active: PR #8 prepares a clean V1 preview with MIT license, security/contributing docs, macOS CI, local preview mode, Codex runtime smoke scripts, and a draft release artifact. Current public metrics are small, so the case is ecosystem relevance and active maintenance rather than adoption.
```

Character count: 312.

## Current Facts

- Repository: public.
- Stars: 0 as of the latest GitHub check.
- Forks: 0 as of the latest GitHub check.
- Open issues: 4.
- Open PRs: 1, draft PR #8.
- CI: macOS `build-test` passes on PR #8.
- Draft release: `v0.1.0-preview`, unpublished.
- Current draft release URL: `https://github.com/klole/mengo-desktop/releases/tag/untagged-c262833bfd31f6c0f5ae`.
- Draft asset: `MengoDesktop-macos-arm64.zip`.
- Draft asset checksum: `sha256:e4d3b21192ac76d1e68aca0cfde4243464f071a4787b8572fd1fe93739c054bd`.
- Release downloads: 0 while draft; refresh after publication.
- Codex smoke: positive CLI/MCP smoke, final-message smoke, missing-MCP negative smoke, generated-skill file/read/invocation smoke, in-app record -> synthesize -> review persistence smoke, and Library -> Review -> Save smoke have passed.
- Notarization: scripted but not complete; Developer ID Application certificate and notarytool profile still required.

## Submission Gate

Do not submit until one of these is true:

- `v0.1.0-preview` is published and explicitly labeled non-notarized, with clean-user smoke status recorded; or
- a Developer ID signed/notarized build is published and Gatekeeper passes.

Before submitting, refresh:

- star/fork counts with `scripts/codex-oss-application-status.sh`,
- release URL and download count with `scripts/codex-oss-application-status.sh`,
- latest CI status with `scripts/codex-oss-application-status.sh`,
- final manual smoke status,
- OpenAI Organization ID.

## Do Not Claim

- Do not claim broad adoption unless repo metrics change.
- Do not use upstream screenpipe stars as Mengo Desktop stars.
- Do not claim notarization until verified.
- Do not claim Codex as the default runtime until the in-app broken-runtime alert and full clean-user manual matrix pass.
