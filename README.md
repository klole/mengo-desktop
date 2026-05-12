# ScreenpipeMenu

A tiny macOS menu bar app that runs [screenpipe](https://github.com/screenpipe/screenpipe) — your local AI memory of screen + mic + accessibility tree. No Node, no Terminal commands once installed. 100% local; nothing leaves your Mac.

## Install (for coworkers — easiest way)

In **Claude Code**, paste:

> Install this for me: https://github.com/klole/screenpipe-menu

Claude Code will read `CLAUDE.md`, clone, run `install.sh`, and tell you what to do about permissions. Total time: ~3 minutes. No `sudo` required (installs into `~/Applications/`).

## Install (manual)

```bash
git clone https://github.com/klole/screenpipe-menu
cd screenpipe-menu
./install.sh                                # build (or download release), install, launch
```

Then grant **Screen Recording** and **Microphone** permissions when prompted (System Settings → Privacy & Security).

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon (arm64) for pre-built releases — Intel Macs need to rebuild from source
- Xcode 16+ / Swift 6 (only if building from source)

## What it does

Once running, it sits in your menu bar as **● Recording**. Click to:
- Pause / resume audio (without restarting the recorder)
- Pause / resume screen capture
- Open your data folder (`~/.screenpipe`)
- Open the log file
- Open Privacy Settings (one-click to where you grant permissions)

The data is queryable via Claude Code's MCP integration — `claude mcp add screenpipe ...` to enable, then ask Claude things like *"what was I working on 30 minutes ago?"* or *"summarize today's meetings"*.

## Specs

- ~150 MB on disk (the recorder binary + ML models for Parakeet ASR are bundled)
- 5–10% CPU, 0.5–3 GB RAM while recording
- ~20 GB/month of recordings (configurable in screenpipe's defaults; data dir is `~/.screenpipe`)
- All processing is on-device. Audio transcription uses Parakeet (NVIDIA OSS, English-only) on Apple Silicon's GPU via MLX.

## Build from source / developer setup

```bash
./bootstrap-cert.sh   # one-time: creates a self-signed cert in your keychain for stable signing
./build.sh            # produces ScreenpipeMenu.app and ScreenpipeMenu.zip
```

`bootstrap-cert.sh` is optional but recommended for active development — without it, every rebuild has a new code hash and macOS will re-prompt for Screen Recording permission. With the stable cert, you grant once and it sticks across rebuilds.

## How the embedded recorder works

`build.sh` downloads the screenpipe binary at build time from npmjs.org, embeds it under `Contents/Helpers/`, and codesigns the whole bundle with a matching identifier. macOS then attributes the spawned recorder's TCC checks (Screen Recording, Microphone) to ScreenpipeMenu.app instead of treating it as a separate process — which is what lets one permission grant cover the whole thing.

The .app launches the recorder as a child process and talks to it on `http://127.0.0.1:3030`. When the .app quits, the recorder gets SIGTERM (then SIGKILL after 3 s).

## License

MIT. Unaffiliated with the upstream screenpipe project.
