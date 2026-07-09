# Mengo Desktop V1 Manual Smoke Test

Run this checklist before publishing a V1 or V1-preview release.

## Fresh Install

- [x] Scripted clean-home check: `HOME=$(mktemp -d) swift test` passes with 186 tests, 0 failures.
- [x] Latest local full test run after Codex path normalization: `swift test` passes with 189 tests, 0 failures.
- [ ] Download the release zip.
- [ ] Verify checksum if one is published.
- [ ] Unzip `MengoDesktop.app`.
- [ ] Run `codesign --verify --deep --strict --verbose=2 MengoDesktop.app`.
- [ ] Run `spctl --assess --type execute -vv MengoDesktop.app`, or confirm the release is explicitly labeled non-notarized preview.
- [ ] Move the app to `~/Applications`.
- [ ] Launch from Finder.
- [ ] Grant Screen Recording permission.
- [ ] Grant Microphone permission.
- [ ] Quit and relaunch.
- [ ] Recorder reaches a healthy/recording state.

## Memory

- [ ] Start recording.
- [ ] Use several apps/windows.
- [ ] Search recent memory.
- [ ] Pause recording.
- [ ] Resume recording.
- [ ] Confirm errors are understandable if the screenpipe helper is unavailable.

## Flow

- [ ] Start flow recording from the button.
- [ ] Start flow recording from the hotkey.
- [ ] Narrate a simple workflow.
- [ ] Stop recording.
- [ ] Synthesize with the selected runtime.
- [ ] Review generated `SKILL.md`.
- [ ] Edit name, description, and at least one parameter.
- [ ] Save.
- [ ] Confirm `SKILL.md`, `flow.json`, and `frames/` exist.
- [ ] Invoke the skill from the selected runtime.
- [ ] Delete the skill from Library.
- [ ] Confirm files are removed.

## Codex Runtime

- [x] Scripted preflight: `codex --version` works locally (`codex-cli 0.143.0`).
- [x] Scripted preflight: `codex mcp list` includes `screenpipe`.
- [x] Scripted preflight: `codex exec ... --output-last-message <file>` writes the final JSON line Mengo parses.
- [x] Select Codex in Settings.
- [x] Confirm preflight detects the Codex executable.
- [x] Complete record -> synthesize -> review. Local smoke created `~/.claude/skills/record-mengo-flow-skill/` and persisted the library path to that slug directory.
- [x] Re-open generated skill from Library into Flow Review, Save, and confirm the UI exits review back to Flow idle.
- [x] Scripted negative preflight: `MENGO_CODEX_SMOKE_NEGATIVE=missing-mcp scripts/smoke-codex-runtime.sh` fails through the missing-screenpipe-MCP path and prints the Codex setup command.
- [x] Scripted generated-skill file smoke: `scripts/smoke-generated-skill.sh` verifies the generated skill directory, `SKILL.md`, and valid `flow.json`.
- [ ] Break Codex setup in the app and confirm the GUI alert mentions Codex/screenpipe MCP.
- [ ] Optional model-backed generated-skill read smoke: `MENGO_SKILL_SMOKE_RUN_MODEL=1 scripts/smoke-generated-skill.sh`.

Repeat the scripted preflight with:

```bash
scripts/smoke-codex-runtime.sh
MENGO_CODEX_SMOKE_RUN_MODEL=1 scripts/smoke-codex-runtime.sh
MENGO_CODEX_SMOKE_NEGATIVE=missing-mcp scripts/smoke-codex-runtime.sh
scripts/smoke-generated-skill.sh
MENGO_SKILL_SMOKE_RUN_MODEL=1 scripts/smoke-generated-skill.sh
```

## Claude Code Runtime

- [ ] Select Claude Code in Settings.
- [ ] Confirm `claude mcp add screenpipe -s user -- npx -y screenpipe-mcp` setup.
- [ ] Complete record -> synthesize -> review -> save.
- [ ] Break Claude setup and confirm the error mentions Claude Code.

## Account/Preview State

- [ ] Launch without preview account.
- [ ] Click **Continue in local preview** and confirm the main app opens.
- [ ] Launch with `MENGO_PREVIEW_ACCOUNT=free`.
- [ ] Launch with `MENGO_PREVIEW_ACCOUNT=pro`.
- [ ] Sign out while idle.
- [ ] Sign out while recording and confirm recording stops.
- [ ] Sign out while reviewing and confirm no generated files are silently deleted.

## Failure States

- [ ] Missing runtime executable.
- [ ] Missing MCP setup.
- [ ] Screen Recording denied.
- [ ] Microphone denied.
- [ ] Skills output directory not writable.
- [ ] Duplicate skill name.
- [ ] Network unavailable if hosted account is enabled.
