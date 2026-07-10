# Mengo Desktop

A macOS app that quietly records your screen, mic, and accessibility tree on-device, then turns what you did into reusable AI skills.

Free and open source. No Mengo account, sign-in, subscription, or feature limits.
Your recordings and app data stay on your Mac.

## Install

Download `MengoDesktop.zip` from the latest GitHub release, unzip it, and move
`MengoDesktop.app` into `~/Applications`. No account or `sudo` is required.

To install from source:

```bash
git clone https://github.com/klole/mengo-desktop
cd mengo-desktop
./install.sh
```

Then grant **Screen Recording** and **Microphone** when macOS asks (System Settings → Privacy & Security).

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon (arm64)
- Xcode 16+ / Swift 6 (only if building from source — `install.sh` downloads a prebuilt release when one is published)
- For fully local Flow synthesis: [Ollama](https://ollama.com) plus the Codex CLI in OSS mode and a tool-capable local model (recommended: `gpt-oss:20b`); no account or API key is required
- Optional: authenticated Claude Code or Codex for cloud-backed synthesis

Mengo defaults to the fully local Ollama runtime. Claude Code and cloud Codex
remain optional and may require an account or paid plan under their own terms.

## What's inside

The app has five panes:

- **Memory** — what you've recorded today / this week / this month, top apps, recent sessions, and on-device insights
- **Flow** — record a demonstration, narrate what you're doing, and Mengo turns it into a Claude Code / Codex skill
- **Library** — your saved flows
- **Studio** — visually edit a saved flow's steps before re-running
- **Settings** — choose the synthesis runtime, configure startup behavior, and open logs or data folders

The recorder (`screenpipe` under the hood) runs as a child process bundled inside the app and talks to the UI on `http://127.0.0.1:3030`. When the app quits, the recorder gets SIGTERM.

## Specs

- ~150 MB on disk (recorder binary + Parakeet ASR models bundled)
- 5–10% CPU, 0.5–3 GB RAM while recording
- ~20 GB/month of recordings (data dir: `~/.screenpipe`)
- Recording, indexing, and audio transcription run on-device via Parakeet (Apple Silicon MLX).
- Local Ollama synthesis stays on-device. If you select Claude Code or cloud Codex, selected recording context is sent according to that provider's terms.

## Build from source

```bash
./bootstrap-cert.sh   # one-time: self-signed cert so macOS doesn't re-prompt every rebuild
./build-mengo.sh      # produces the verified MengoDesktop.zip artifact
./install.sh          # verifies, installs to ~/Applications, and launches it
```

`bootstrap-cert.sh` is optional but recommended during development — without it, every rebuild has a new code hash and macOS re-prompts for Screen Recording permission.

## Beta feedback

Open an issue on this repo or message me directly with:
- macOS version + chip
- what you tried to do
- recorder log: `~/Library/Logs/MengoDesktop/recorder.log`
- app log: `~/Library/Logs/MengoDesktop/app.log`

## License

[MIT](LICENSE). Bundled dependencies are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
