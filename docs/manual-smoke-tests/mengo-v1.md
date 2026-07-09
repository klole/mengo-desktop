# Mengo Desktop V1 Manual Smoke Test

Run this checklist before publishing a V1 or V1-preview release.

## Fresh Install

- [x] Scripted clean-home check: `HOME=$(mktemp -d) swift test` passes with 186 tests, 0 failures.
- [x] Latest local full test run after Codex broken-MCP alert coverage: `swift test` passes with 191 tests, 0 failures.
- [x] Scripted published-asset smoke: `MENGO_RELEASE_DOWNLOAD_SMOKE=1 scripts/release-readiness-status.sh` downloads the release zip, verifies checksum, extracts `MengoDesktop.app` with `ditto`, runs codesign verification, and confirms the expected non-notarized Gatekeeper rejection.
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
- [x] Optional model-backed generated-skill read smoke: `MENGO_SKILL_SMOKE_RUN_MODEL=1 scripts/smoke-generated-skill.sh` returned `{"status":"ok","readSkill":true,"readFlow":true}`.
- [x] Terminal Codex generated-skill invocation smoke: `MENGO_SKILL_SMOKE_RUN_MODEL=1 MENGO_SKILL_SMOKE_INVOKE=1 scripts/smoke-generated-skill.sh` returned `{"status":"ok","readSkill":true,"readFlow":true,"invoked":true,"stepCount":5}`.
- [x] Scripted clean generated-skill invocation smoke: `scripts/smoke-clean-generated-skill.sh` copied the generated skill into a temporary `.claude/skills` home and Codex returned `{"status":"ok","readSkill":true,"readFlow":true,"invoked":true,"stepCount":5}`.
- [x] Unit coverage: `FlowControllerTests` verifies the missing Codex/screenpipe MCP alert names Codex, includes `codex mcp add screenpipe -- npx -y screenpipe-mcp`, and exposes "Copy command" / "OK" actions.
- [ ] Break Codex setup in the app and confirm the GUI alert mentions Codex/screenpipe MCP.
- [ ] Clean-user in-app generated-skill invocation from the selected runtime.

Repeat the scripted preflight with:

```bash
scripts/smoke-codex-runtime.sh
MENGO_CODEX_SMOKE_RUN_MODEL=1 scripts/smoke-codex-runtime.sh
MENGO_CODEX_SMOKE_NEGATIVE=missing-mcp scripts/smoke-codex-runtime.sh
scripts/smoke-generated-skill.sh
MENGO_SKILL_SMOKE_RUN_MODEL=1 scripts/smoke-generated-skill.sh
MENGO_SKILL_SMOKE_RUN_MODEL=1 MENGO_SKILL_SMOKE_INVOKE=1 scripts/smoke-generated-skill.sh
scripts/smoke-clean-generated-skill.sh
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
