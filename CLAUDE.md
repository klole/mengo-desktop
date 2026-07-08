# CLAUDE.md - Agent Setup Instructions

You are helping install or develop Mengo Desktop from this repository.

## What This Is

Mengo Desktop is a macOS app that runs a bundled screenpipe recorder and provides local memory plus workflow-to-skill capture. The expected installed app is:

```text
~/Applications/MengoDesktop.app
```

Do not install or launch the legacy ScreenpipeMenu or ScreenpipeFlow apps unless the user explicitly asks for legacy behavior.

## Install Procedure

From the repository root:

```bash
./install.sh
```

The installer checks prerequisites, downloads the latest `MengoDesktop` release asset when available, falls back to building from source, installs into `~/Applications`, removes quarantine metadata for local preview use, stops prior Mengo instances, and launches the app.

No `sudo` should be needed.

## After Launch

Tell the user to grant:

1. Screen Recording permission for Mengo Desktop.
2. Microphone permission for Mengo Desktop.

After permissions are granted, the recorder should move to a healthy or recording state. If it does not, ask the user to relaunch the app and check:

```text
~/Library/Logs/MengoDesktop/recorder.log
```

## Developer Commands

```bash
swift test --filter MengoDesktopTests
./build-mengo.sh
codesign --verify --deep --strict --verbose=2 MengoDesktop.app
```

Full `swift test` is a V1 gate, but legacy target cleanup may be required before it is green.

## Runtime Setup

For Claude Code synthesis:

```bash
claude mcp add screenpipe -s user -- npx -y screenpipe-mcp
```

For Codex synthesis, install the Codex CLI and select Codex in Mengo Settings.

## Do Not

- Do not run `sudo` for the installer.
- Do not try to grant macOS privacy permissions programmatically.
- Do not delete `~/.screenpipe` or runtime skill directories without explicit user confirmation.
- Do not claim notarization is complete unless `spctl --assess --type execute` passes on the release artifact.
