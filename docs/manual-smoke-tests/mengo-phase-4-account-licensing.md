# Mengo Desktop — Phase 4 manual smoke checklist

The mengo.ai endpoints and Stripe checkout are out of scope for this phase (the
website/Stripe owner builds them). Account flows here use the `MENGO_DEV_ACCOUNT`
env-var hatch until the website ships.

## Build & tests (scriptable)

- [ ] `swift build` — succeeds.
- [ ] `swift test` — full suite green.
- [ ] `./build-mengo.sh` — produces `MengoDesktop.app` that codesigns cleanly.
- [ ] `codesign --verify --deep --strict ~/Applications/MengoDesktop.app` — clean.
- [ ] `open "mengo://refresh"` while the app is running — the deep link reaches
  the app (no crash; an `account.refresh()` line appears in `~/Library/Logs/MengoDesktop/app.log`).

## Sign-in hard wall

- [ ] Cold launch with **no** cached session and **no** `MENGO_DEV_ACCOUNT` —
  the sign-in screen shows; no sidebar / no Memory pane.
- [ ] `MENGO_DEV_ACCOUNT=pro swift run MengoDesktop` (or via `MengoDesktop.app`'s
  env launch) — app opens straight to Memory; Settings → Account shows **Pro**;
  no "Purchase Mengo Pro" button in the sidebar.
- [ ] `MENGO_DEV_ACCOUNT=free` — Settings → Account shows **Free** + "0 of 3 flows
  used"; sidebar shows "Purchase Mengo Pro" + the "N of 3 free flows used" caption
  above the Settings row; Settings sits pinned at the sidebar bottom.

## Free / Pro gating

- [ ] With `MENGO_DEV_ACCOUNT=free`, record + Save 3 flows — the sidebar counter
  ticks "0 of 3" → "3 of 3".
- [ ] Record a 4th flow and click **Save** — the "You've used all your free flows"
  alert appears; **Cancel** keeps the flow in `.reviewing` (nothing lost).
- [ ] Delete one of the existing 3 flows from the Library — Save the held flow
  → it lands; counter back to "3 of 3".
- [ ] `MENGO_DEV_ACCOUNT=pro` — record + Save unlimited flows; no alert; no
  Purchase button anywhere.

## Settings → Synthesis model

- [ ] Default is **Claude Code**.
- [ ] Pick **Codex** — record a real task → synthesis runs via `codex exec`
  (check `~/Library/Logs/MengoDesktop/synthesis-*.log` for the `codex exec`
  invocation; or the preflight dialog tells you to run
  `codex mcp add screenpipe -- npx -y screenpipe-mcp` and offers a [Copy
  command] button).
- [ ] Switch back to **Claude Code** — synthesis still works.
- [ ] **Claude Cowork** and **Bring your own LLM (MCP)** rows are visible but
  greyed out and show a "coming soon" caption; clicking them is a no-op.

## Settings → Startup

- [ ] Toggle "Open Mengo Desktop at login" on — System Settings › General ›
  Login Items lists Mengo Desktop; toggle off — gone.
  - If the toggle reverts and a red caption appears, the app isn't in a signed
    location (ad-hoc-signed `swift run` builds can't register a login item).
- [ ] Toggle "Start recording when Mengo opens" **off** → quit → relaunch —
  recorder stays idle until you start it from the Memory pane.
- [ ] Toggle on → relaunch — recorder auto-starts.

## Settings → Logs & data

- [ ] "Open recorder log" opens the screenpipe recorder log file.
- [ ] "Open Mengo log" opens `~/Library/Logs/MengoDesktop/app.log`.
- [ ] "Reveal recordings folder" opens `~/.screenpipe/`.
- [ ] "Reveal Mengo data folder" opens `~/Library/Application Support/MengoDesktop/`.

## Sign out

- [ ] Settings → Account → **Sign out** — the hard wall reappears immediately;
  the recorder stops on next launch (it's gated by sign-in + startRecordingOnLaunch).
- [ ] Re-launch with `MENGO_DEV_ACCOUNT=pro` — access restored.

## Deep links

- [ ] `open "mengo://refresh"` while running — no crash; `app.log` shows the link
  was handled.
- [ ] `open "mengo://auth?token=test123"` while running — `app.log` shows
  `handleAuthDeepLink` ran (it'll fail against the empty mengo.ai server —
  expected; the test only confirms the link is routed).
- [ ] `open "mengo://garbage"` — ignored; `app.log` shows `ignored deep link`.

## Menu bar (signed-out / Free)

- [ ] When signed out, the menu-bar dropdown shows only "Sign in to Mengo
  Desktop…" + "Quit Mengo Desktop". Nothing else.
- [ ] When signed in as **Free**, the dropdown includes an "Upgrade to Mengo
  Pro…" item just above Settings.
- [ ] When signed in as **Pro**, the Upgrade item is hidden.

## App bundle

- [ ] `MengoDesktop.app/Contents/Info.plist` includes `CFBundleURLTypes` with
  scheme `mengo` (verify with `defaults read $(pwd)/MengoDesktop.app/Contents/Info CFBundleURLTypes`).
- [ ] `open "mengo://refresh"` reaches the `.app` after the install (the system
  must associate the URL scheme with the bundle).
