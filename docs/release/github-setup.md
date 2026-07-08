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
- Manual smoke test status is recorded in `docs/manual-smoke-tests/mengo-v1.md`.
