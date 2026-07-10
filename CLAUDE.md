# CLAUDE.md — Setup instructions for Claude Code

You (Claude Code) are helping someone install Mengo Desktop. Follow these steps in order. Run commands non-interactively; report progress; don't ask for confirmation on routine steps.

## What this is

Mengo Desktop is a macOS app that records your screen, mic, and accessibility tree locally and turns sessions into reusable AI skills. The bundled `screenpipe` helper does the recording; the app provides the Memory / Flow / Library / Studio panes around it.

## The job

End state: `~/Applications/MengoDesktop.app` installed and launched, the user has granted Screen Recording + Microphone permissions, and the in-app Memory pane shows recent frames within ~30 seconds.

## Procedure

### 1. Clone if needed

If you're not already inside this repo, clone it:

```bash
git clone https://github.com/klole/mengo-desktop
cd mengo-desktop
```

### 2. Run the installer

```bash
./install.sh
```

This handles: prerequisites check (macOS 15+, arm64), verified download of a signed prebuilt release (or a build from source if Swift 6+ is available), install to `~/Applications/`, and launch. **No `sudo`** — `~/Applications/` is user-scoped.

Report whatever `install.sh` prints as you go.

### 3. If `install.sh` fails

Read its output carefully. Common failure modes:

| Error | Fix |
|---|---|
| `macOS 15 (Sequoia) or later` | User's Mac is too old. Stop here — they need to upgrade. |
| `arm64` only | User is on an Intel Mac. Stop here. |
| `swift not found` AND no release available | User needs Xcode 16+ from the App Store. Stop and ask them to re-run after install. |
| `Swift 6+ required` | User has older Xcode. Tell them to update. Stop. |
| Download failed | Connection or GitHub problem. Ask them to retry. |

### 4. After successful launch — tell the user this exactly

```
Mengo Desktop is launched. Two things to do right now:

1. A "Screen Recording" permission dialog will appear (or already has).
   Click "Open System Settings", find MengoDesktop in the list, and
   toggle it ON. Then close System Settings.

2. Accept the "Microphone" permission prompt when it appears.

Once both are granted, the Memory pane will start showing recent frames
within ~15 seconds. If it stays empty, check the recorder log at
~/Library/Logs/MengoDesktop/recorder.log and click "Restart recorder"
from the Settings pane.

The sidebar has Memory, Flow, Library, and Studio. All recording is
local — nothing leaves your Mac. Data lives in ~/.screenpipe.
```

### 5. Optionally verify

After ~30 seconds, confirm that the in-app Memory pane shows recent frames and
the recorder status is healthy. If it does not, inspect
`~/Library/Logs/MengoDesktop/recorder.log` and confirm permissions in System
Settings → Privacy & Security. Never extract or print the recorder's private
per-launch token.

## What you should NOT do

- Don't run `sudo`. `install.sh` doesn't need it.
- Don't try to grant macOS permissions programmatically — only the user can click those toggles. Just tell them what to do.
- Don't modify `~/.screenpipe/` — that's the recorder's own data dir.
