# CLAUDE.md — Setup instructions for Claude Code

You (Claude Code) are helping a coworker install ScreenpipeMenu. Follow these steps in order. Run commands non-interactively; report progress; don't ask for confirmation on routine steps.

## What this is

ScreenpipeMenu is a tiny macOS menu bar app that runs screenpipe (a local 24/7 recorder of screen + mic + accessibility tree). Once installed and permissioned, it sits in the menu bar and records everything locally — nothing leaves the Mac.

## The job

End state: `~/Applications/ScreenpipeMenu.app` installed, launched, and the user has granted Screen Recording + Microphone permissions. They should see green "Recording" in the menu bar within ~30 seconds.

## Procedure

### 1. Clone if needed

If you're not already inside this repo, clone it:

```bash
git clone <THIS-REPO-URL>
cd <repo-name>
```

### 2. Run the installer

```bash
./install.sh
```

This script handles everything: prerequisites check (macOS 15+, arm64), pre-built release download (or fallback to building from source if Swift 6+ is available), install to `~/Applications/`, quarantine removal, launch. **No `sudo` involved** — installs to user-scoped `~/Applications/` so it doesn't need elevated permissions.

Report whatever `install.sh` prints to the user as you go.

### 3. If `install.sh` fails

Read its output carefully. Common failure modes and what to tell the user:

| Error | Fix |
|---|---|
| `macOS 15 (Sequoia) or later` | User's Mac is too old. They need to upgrade macOS. Stop here. |
| `arm64` only | User is on an Intel Mac. Stop here, point them at the README for Intel build instructions. |
| `swift not found` AND no release available | User needs Xcode 16+ from the App Store, then `xcode-select --install`. Tell them, stop, and ask them to re-run you when done. |
| `Swift 6+ required` | User has older Xcode. Tell them to update Xcode, stop, re-run when done. |
| Download failed (no internet, GitHub down) | Tell them to check connection and re-run. |

### 4. After successful launch — tell the user this exactly

```
ScreenpipeMenu is launched. Two things you must do right now:

1. A "Screen Recording" permission dialog will appear (or already has).
   Click "Open System Settings", find ScreenpipeMenu in the list, and
   toggle it ON. Then close System Settings.

2. Accept the "Microphone" permission prompt when it appears.

After both are granted, look at your menu bar (top-right corner).
Within ~15 seconds the icon should turn GREEN and the text should read
"Recording". If it's stuck on "Starting" or shows "Error", click the
icon → "Restart recorder".

The menu has pause/resume controls for audio and screen, a link to
your local data folder (~/.screenpipe), and Quit. All recording is
local; nothing leaves your Mac.
```

### 5. Optionally verify

After ~30 seconds (giving time for permission grant), verify:

```bash
curl -s http://127.0.0.1:3030/health | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('Recorder:', d.get('status'))
print('Video:', d.get('frame_status'))
print('Audio:', d.get('audio_status'))
print('Frames so far:', d.get('pipeline', {}).get('frames_captured', 0))
"
```

If `Recorder: healthy`, you're done. Otherwise, tell the user to check `~/Library/Logs/ScreenpipeMenu/recorder.log` and grant any pending permissions.

## What you should NOT do

- Don't run `sudo`. `install.sh` doesn't need it.
- Don't try to grant macOS permissions programmatically — only the user can click those toggles. Just tell them what to do.
- Don't try to use Claude Code's MCP integration with screenpipe in this session — MCP loads at session start, so it won't be available here. Tell the user they can `claude mcp add screenpipe -s user -- npx -y screenpipe-mcp` in a new session if they want Claude to query their recordings.
- Don't modify `~/.screenpipe/` — that's screenpipe's own data dir.
