# Codex for OSS Application Notes

Use this after the public V1 preview release is published and the GitHub repo metadata is current.

## Repository

```text
https://github.com/klole/mengo-desktop
```

## Role

Primary maintainer.

## Qualification Answer

Mengo Desktop is an open-source macOS app that turns local screen/audio workflow demonstrations into reusable AI skills for Codex/Claude-style agents. It builds on the screenpipe local recording ecosystem and targets maintainer automation: capturing repeated release, triage, review, and repo workflows so they can be replayed reliably. I am the primary maintainer and am preparing its first clean OSS V1 release.

## API Credit Usage Answer

I would use API credits for core maintainer workflows: automated PR review, release checklist generation, security-oriented review, docs maintenance, and improving Mengo's skill synthesis/evaluation loop. Credits would also help test Codex-based workflows that convert maintainer actions into reusable skills, directly improving the open-source project.

## Additional Context Answer

Mengo is early, but it is directly aligned with Codex maintainer workflows: it helps capture how maintainers actually work and turn those actions into reusable automation. The V1 plan includes public docs, license/security policy, CI, preview releases, and Codex runtime smoke tests.

## Facts to Fill Before Submitting

- Current star count: 0 as of 2026-07-08.
- Current fork count: 0 as of 2026-07-08.
- Current release tag: existing `v1.0.0` release is pre-cleanup and should not be used as the Mengo Desktop V1 evidence; a draft `v0.1.0-preview` prerelease is prepared but not published.
- Release download count: 0 on the draft `MengoDesktop-macos-arm64.zip` asset; fill again after publication.
- Draft asset checksum after the Library review-navigation fix: `sha256:e4d3b21192ac76d1e68aca0cfde4243464f071a4787b8572fd1fe93739c054bd`.
- CI status: macOS `build-test` passes on draft PR #8; re-check the latest branch head immediately before applying.
- Draft PR: https://github.com/klole/mengo-desktop/pull/8
- Draft release: https://github.com/klole/mengo-desktop/releases/tag/untagged-1364ef715b4b6741d7dd
- Demo video/GIF: `docs/assets/mengo-desktop-preview.gif` exists; replace with a real record-to-skill walkthrough after the full app smoke passes.
- Codex runtime smoke result: scripted CLI/MCP/final-message smoke passed locally with `codex-cli 0.143.0`; scripted missing-MCP negative smoke prints the Codex setup command; local in-app Codex record-to-synthesize-to-review persistence smoke passed after normalizing parent output directories to the generated skill slug directory; Library re-open -> Review -> Save UI smoke passed after wiring Library review navigation to switch back to Flow.
- Notarization status: notarization path is scripted, but a Developer ID Application certificate and notarytool profile are still required.

## Do Not Claim

- Do not claim broad adoption unless the public repo metrics support it.
- Do not use upstream screenpipe stars as Mengo Desktop stars.
- Do not claim notarization until verified.
- Do not claim Codex as the default runtime until the broken-runtime error path and full clean-user manual matrix pass.

## Stronger Final Version Should Mention

- Published V1 preview release.
- Passing CI.
- Public roadmap/issues.
- Security and privacy docs.
- Local preview mode that lets OSS users run without hosted backend.
- Exact ways Codex credits will improve maintainer workflows in this repo.
