# Changelog

All notable changes to Mengo Desktop are documented here.

## Unreleased

### Added

- Account-free local Ollama synthesis through Codex OSS mode.
- Editable Studio timeline and canvas.
- Natural-language flow editing and SKILL.md regeneration.
- Developer ID signing and notarization release workflow.
- CI, security policy, contributor guide, and third-party notices.

### Changed

- Mengo Desktop is the repository's only app target.
- Runtime subprocesses use scoped permissions instead of dangerous bypass flags.
- The Screenpipe CLI and Screenpipe MCP dependencies are pinned to MIT-licensed revisions.
- Review edits now update both `flow.json` and `SKILL.md`.

### Removed

- Mengo account, magic-link authentication, licensing, paid feature gates, and flow limits.
- Unfinished import, template, Cowork, and custom-MCP controls.
- Legacy ScreenpipeMenu and ScreenpipeFlow app targets.
