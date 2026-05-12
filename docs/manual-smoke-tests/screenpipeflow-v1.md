# ScreenpipeFlow V1 — manual smoke checklist

Run this before tagging a V1.x release. Each item should pass before shipping.

## Preconditions
- macOS 15+, Apple Silicon
- ScreenpipeMenu.app installed and running ("Recording" status in green)
- Claude Code CLI installed (`which claude` returns a path)
- screenpipe MCP configured for Claude Code (`claude mcp list` shows screenpipe)

## A. App lifecycle
- [ ] Launch `~/Applications/ScreenpipeFlow.app` from Finder — menu bar icon appears (`waveform.circle`).
- [ ] Click the icon — dropdown shows expected items (Start recording, Grab last 5 minutes…, Open library, Open skills folder, Open app log, Quit).
- [ ] Quit via the menu — process terminates cleanly (`pgrep -f ScreenpipeFlow.app/Contents/MacOS` returns nothing).

## B. Mode A — Proactive recording
- [ ] Click Start recording. HUD appears top-right with red dot, 0:00 timer, hint "Narrate what you're doing.", Stop button.
- [ ] Do a narratable task for 30–60s (open a webpage, copy a value, paste somewhere) while speaking out loud.
- [ ] Click Stop. HUD disappears. Menu bar label changes to "Synth…".
- [ ] Within ~30s–2min, the menu label changes to "Review".
- [ ] Review window opens automatically (or click "Reopen Review window" from the menu).
- [ ] SKILL.md preview renders. Description matches what you narrated.
- [ ] Click Save and close. The skill exists at `~/.claude/skills/<slug>/` containing SKILL.md, flow.json, and frames/.
- [ ] Invoke the skill from a new Claude Code session. Claude reads SKILL.md and can execute the demonstrated intent.

## C. Mode C — Retroactive recording
- [ ] Be doing something narratable for the last 10 minutes (recorded by screenpipe).
- [ ] Click "Grab last 5 minutes…". Timeline window opens.
- [ ] List populates with OCR events: timestamp + app name + window name.
- [ ] Change "Look back" to 1 hour — list grows.
- [ ] Pick a row near where the task started. "Selected window: …" updates at the bottom.
- [ ] Click "Begin from here." Window closes. HUD appears with `(Buffer: Xm Ys)` indicator.
- [ ] Narrate briefly: "Earlier I was doing X. Now I'm finishing by doing Y."
- [ ] Click Stop. Synthesis runs.
- [ ] Verify SKILL.md mentions earlier steps as inferred from observation.

## D. Variable callouts (narration-driven)
- [ ] Start a recording.
- [ ] Mid-recording narrate: "I'm typing in my email myemail@example.com — that should be a variable, call it user_email."
- [ ] Finish task. Stop.
- [ ] In the Review window, verify SKILL.md frontmatter or `## Parameters` section includes `user_email`.

## E. Regenerate-with-feedback
- [ ] After any synthesis, click "Regenerate with feedback…"
- [ ] Type "Make the description shorter." Submit.
- [ ] A new synthesis runs and updates the skill directory.

## F. Error paths
- [ ] Quit ScreenpipeMenu. Click Start recording in ScreenpipeFlow. Expected dialog: "screenpipe is not running".
- [ ] Restart ScreenpipeMenu. In its menu, click "Pause audio." Click Start in ScreenpipeFlow. Expected: "Microphone capture is paused".
- [ ] Temporarily rename claude (e.g. `sudo mv /opt/homebrew/bin/claude /tmp/`). Click Start. Expected: "Claude Code CLI not found." Restore.
- [ ] Click Start, then Stop within 10s. Expected: "Recording too short" alert.

## G. Crash recovery
- [ ] Click Start recording. After 5 seconds, force-kill: `pkill -9 -f ScreenpipeFlow.app/Contents/MacOS`.
- [ ] Relaunch ScreenpipeFlow.app from Finder. Expected: "An earlier recording was interrupted at HH:MM:SS…" dialog. Click OK.
- [ ] Verify `~/Library/Application Support/ScreenpipeFlow/recovery/` is empty after the dialog closes.

## H. Library
- [ ] Open the library window. Verify all created skills appear with correct names and dates.
- [ ] Click Open for a skill — Finder reveals its directory.
- [ ] Click Review for a skill — Review window opens with its SKILL.md.
- [ ] Click Delete for a skill — disappears from library; directory removed from `~/.claude/skills/`.

## I. Hotkeys
- [ ] With ScreenpipeFlow running and focus elsewhere: press `⌃⌥R`. Recording starts (HUD appears).
- [ ] Press `⌃⌥R` again. Recording stops.
- [ ] Press `⌃⌥G`. Timeline window opens.

## J. Performance
- [ ] Leave the app running idle for 30+ minutes. Activity Monitor: CPU < 1%, RSS < 100 MB.
- [ ] Quit and re-launch — library re-populates from disk on init.

## K. Distribution
- [ ] Run `./build-flow.sh`. `ScreenpipeFlow.app` and `ScreenpipeFlow.zip` produced.
- [ ] Double-click the .app in Finder. Launches cleanly. (If Gatekeeper blocks, run `xattr -dr com.apple.quarantine ScreenpipeFlow.app` first.)
