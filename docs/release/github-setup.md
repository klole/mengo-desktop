# GitHub Setup Checklist

Run these once the local V1 prep branch is pushed.

## Topics

Recommended repository topics:

```text
macos
swift
swiftui
screenpipe
codex
claude-code
skills
workflow-automation
local-first
ai-memory
```

## Labels

Recommended labels:

```text
v1
docs
bug
enhancement
release
runtime
privacy
security
good first issue
codex
packaging
manual-smoke
```

## Seed Issues

Created on 2026-07-08:

1. [release: complete Developer ID signing and notarization](https://github.com/klole/mengo-desktop/issues/1)
2. [runtime: smoke-test Codex record-to-skill path](https://github.com/klole/mengo-desktop/issues/2)
3. [qa: run Mengo Desktop V1 manual smoke checklist](https://github.com/klole/mengo-desktop/issues/3)
4. [build: decide legacy ScreenpipeMenu and ScreenpipeFlow target strategy](https://github.com/klole/mengo-desktop/issues/4)
5. [release: publish v0.1.0 preview release](https://github.com/klole/mengo-desktop/issues/5)
6. [docs: add demo GIF or short walkthrough video](https://github.com/klole/mengo-desktop/issues/6)
7. [packaging: verify x86_64 helper packaging or document arm64-only support](https://github.com/klole/mengo-desktop/issues/7)

## Release Gate

Do not publish the preview release until:

- `swift test` passes.
- `./build-mengo.sh` passes.
- `codesign --verify --deep --strict --verbose=2 MengoDesktop.app` passes.
- `spctl --assess --type execute -vv MengoDesktop.app` result is documented.
- `docs/release/v0.1.0-preview.md` checksum is regenerated from the final zip.
- `scripts/release-readiness-status.sh` passes.
- After publishing, `MENGO_EXPECT_RELEASE_DRAFT=0 scripts/release-readiness-status.sh` passes.
- Manual smoke test status is recorded in `docs/manual-smoke-tests/mengo-v1.md`.

## Current Pull Request

- Draft PR: https://github.com/klole/mengo-desktop/pull/8
- Branch: `v1-release-readiness`
- CI status after the resource/concurrency fixes: passing macOS `build-test`.

## Signing Status

- Local ad-hoc packaging path works through `./build-mengo.sh`.
- Release notarization path is scripted in `scripts/notarize-mengo.sh`.
- Current local keychain has an Apple Development identity only; a Developer ID Application certificate and notarytool profile are still required before a notarized V1 can be published.

## Draft Release

- Draft prerelease: https://github.com/klole/mengo-desktop/releases/tag/untagged-cd97a45edea4f66685a4
- Intended tag: `v0.1.0-preview`
- Target: `v1-release-readiness`
- Asset: `MengoDesktop-macos-arm64.zip`
- Asset digest reported by GitHub: `sha256:e4d3b21192ac76d1e68aca0cfde4243464f071a4787b8572fd1fe93739c054bd`
- Status: draft, prerelease, not published; release body has been synced with `docs/release/v0.1.0-preview.md`.
