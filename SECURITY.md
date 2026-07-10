# Security policy

## Supported version

Security fixes are applied to the latest release and the current `main` branch.

## Reporting a vulnerability

Please do not open a public issue for vulnerabilities involving recording
access, local data exposure, command execution, model prompt injection, update
integrity, or signing/notarization.

Use GitHub's private vulnerability reporting for this repository:
<https://github.com/klole/mengo-desktop/security/advisories/new>

Include the affected version, reproduction steps, impact, and any suggested
mitigation. Do not include real recordings, transcripts, credentials, or other
people's private data.

## Security model

- Screen, microphone, OCR, transcription, and indexing data are stored locally.
- The default Ollama synthesis runtime is local and requires no account.
- Claude Code and cloud Codex are optional; selecting one can send chosen
  recording context to that provider.
- Model subprocesses receive write access only to the target skill directory.
- Recording synthesis receives only the pinned Screenpipe MCP server; Studio
  edits receive no recorder MCP access.
- Release archives must be Developer ID signed, notarized, stapled, and
  accompanied by a SHA-256 checksum.
