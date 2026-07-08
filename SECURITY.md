# Security Policy

Mengo Desktop records local screen and microphone context through a bundled screenpipe helper. Treat all recordings, generated skills, logs, and runtime prompts as potentially sensitive.

## Supported Versions

Security fixes target the latest public release and the current `main` branch while Mengo is pre-1.0.

## Reporting a Vulnerability

Please do not open public GitHub issues for vulnerabilities, privacy leaks, token handling problems, or recorder behavior that could expose sensitive data.

Report privately by emailing the maintainer or using GitHub's private vulnerability reporting if it is enabled on the repository. Include:

- affected version or commit,
- macOS version and architecture,
- reproduction steps,
- expected and actual behavior,
- whether logs, recordings, or runtime prompts contained sensitive data.

## Local Data and Privacy Model

Mengo stores recorder data locally through screenpipe, normally under `~/.screenpipe`. App logs are written under `~/Library/Logs/MengoDesktop`. Generated skills are written to the selected runtime's skills directory.

Mengo should not intentionally upload recordings. Skill synthesis may pass selected context to the configured runtime, such as Codex or Claude Code, according to that runtime's setup. Review runtime configuration before using Mengo with sensitive work.

## Security Expectations

- Tokens must be stored in Keychain or an equivalent secure store.
- Logs must avoid secrets, auth tokens, and unnecessary raw recorder content.
- Sign-out must stop recording and clear account state.
- Release builds should be signed and notarized before being recommended for general use.
