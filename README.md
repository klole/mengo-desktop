# ScreenpipeMenu

A tiny macOS menu bar app that runs [screenpipe](https://github.com/screenpipe/screenpipe) while it's open. Local-only AI memory of your screen and mic. No Node, no Terminal — double-click and go.

## Install (coworkers, read this)

1. Download `ScreenpipeMenu.zip` and unzip.
2. **First launch only:** right-click `ScreenpipeMenu.app` → **Open** → click **Open** in the dialog. (macOS Gatekeeper blocks unsigned apps until you tell it once. Subsequent launches just double-click.)
3. The first time it runs it'll download the screenpipe binary (~150 MB). The menu bar icon shows a download arrow with a percentage.
4. macOS will ask for **Screen Recording** and **Microphone** permission. Grant both in System Settings → Privacy & Security, then quit and relaunch the app. The menu has an "Open Privacy Settings" item that jumps straight there.
5. Recording status appears in the menu bar (top right). Click the icon for status, pause/resume, and logs.

## Menu

| Item | What it does |
|---|---|
| **Pause audio / Resume audio** | Stops the microphone capture without restarting. Resumes instantly. |
| **Pause screen / Resume screen** | Stops the recorder entirely. Resume takes ~15s (re-loads ML models). |
| **Open data folder** | `~/.screenpipe` — everything screenpipe stores, local. |
| **Open log file** | `~/Library/Logs/ScreenpipeMenu/recorder.log` |
| **Open Privacy Settings** | Fast path to the macOS panel for granting Screen Recording. |
| **Restart recorder / Retry download** | Shown only on errors. |
| **Quit** | Stops recording and exits cleanly. |

## Build from source

Requires Xcode 16+ / Swift 6.0+, macOS 15 (Sequoia) or later.

```bash
git clone <this repo> ScreenpipeMenu
cd ScreenpipeMenu
./build.sh
open ScreenpipeMenu.app
```

`build.sh` produces:
- `ScreenpipeMenu.app` — runnable on this Mac
- `ScreenpipeMenu.zip` — the shareable artifact for coworkers

Run tests with `swift test`.

## Specs

- macOS 15+ (Sequoia)
- Universal binary (arm64 + x86_64)
- ~150 MB binary download on first launch (cached to `~/Library/Application Support/ScreenpipeMenu/`)
- 5–10% CPU, 0.5–3 GB RAM while recording
- ~20 GB / month storage (configurable in screenpipe itself, see `~/.screenpipe/`)
- 100% local; nothing leaves the Mac

## How it works

```
ScreenpipeMenu.app launches
   └─ downloads screenpipe binary from npm registry (first run only)
   └─ spawns: ~/Library/Application Support/ScreenpipeMenu/bin/screenpipe record
              ↓ (env: SCREENPIPE_API_KEY=<random>)
              ↓ HTTP API on 127.0.0.1:3030
   └─ polls /health every 5s
   └─ menu shows status; pause audio = POST /audio/stop
                          pause screen = SIGTERM the recorder
```

Quitting the app sends SIGTERM to the recorder (3s grace, then SIGKILL). If the .app is force-quit by macOS, `applicationWillTerminate` still runs the same cleanup.

## License

Same as [screenpipe](https://github.com/screenpipe/screenpipe) (MIT). This wrapper is unaffiliated with the upstream project.
