# Contributing

Mengo Desktop is preparing for a first OSS V1 release. Contributions that improve release quality, testability, privacy, and the core record-to-skill loop are the priority.

## Setup

Requirements:

- macOS 15 or later
- Xcode 16+
- Swift 6+

Common commands:

```bash
swift build
swift test --filter MengoDesktopTests
./build-mengo.sh
```

Full `swift test` is a V1 gate. If it fails in legacy Screenpipe targets, note that in your PR and keep MengoDesktop tests green.

## Release Plan

Before starting substantial work, read:

```text
docs/release/mengo-desktop-v1-release-plan.md
```

The first priority is making the public repo coherent, then making CI green, then fixing product trust blockers.

## Pull Requests

Good PRs should:

- describe the user-visible behavior change,
- include tests for app logic changes,
- avoid unrelated formatting churn,
- keep legacy Screenpipe changes separate from MengoDesktop changes where possible,
- mention any manual smoke tests run.

## Coding Notes

- Prefer existing SwiftUI and Observation patterns in `Sources/MengoDesktop`.
- Keep recorder and account state transitions explicit and testable.
- Avoid logging secrets, tokens, or raw sensitive recorder content.
- Use temp directories in tests instead of real home-directory paths.

## Manual Smoke Tests

Manual QA lives under:

```text
docs/manual-smoke-tests
```

V1 release candidates should have a completed Mengo V1 smoke checklist before release.
