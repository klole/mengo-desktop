# Mengo Desktop — Phase 4: Account & licensing (+ Settings, runtime selector)

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Roadmap:** [`2026-05-12-mengo-desktop-playbook.md`](2026-05-12-mengo-desktop-playbook.md) — this is Phase 4 ("Account & licensing"), expanded with the user's Settings/runtime/sidebar asks.
**Follows:** Phases 1–3 (shell, Memory, Flow 3a+3b) — merged to `main`. Phase 4 builds on `main`.
**Website:** the licensing/auth contract is consumed by `mengo.ai` (the separate Next.js repo at `~/Desktop/Mengo.ai`, currently a bare skeleton). This spec documents the contract; building those endpoints + the Stripe checkout is **the website/Stripe owner's work, not this spec's**.

## Goal

Mengo Desktop requires a Mengo account. The user signs in once via a magic link emailed by `mengo.ai`; after that the session is cached and the app works fully offline forever (re-validating only when online; never locking out a previously-signed-in user). The account carries an entitlement — **Free** (≤3 saved flows) or **Pro** (unlimited) — surfaced in the UI; a **Purchase Mengo Pro** affordance in the sidebar (Free users only) opens the website already signed-in for Stripe checkout. A new **Settings** pane (replacing the placeholder) lets the user pick the synthesis runtime (Claude Code · Codex · Claude Cowork *(disabled)* · Bring-your-own-LLM-via-MCP *(disabled)*), toggle launch-at-login and start-recording-on-launch, and reach the logs/data folders. The Flow synthesis call site becomes runtime-aware (Claude Code default; Codex fully wired).

Big phase (~25–30 tasks). The implementation plan sequences it internally — roughly: **(A)** account/sign-in/hard-wall/Keychain/`mengo://`; **(B)** Settings pane + `SettingsStore` + runtime abstraction + Codex runtime + startup options + logs; **(C)** Free/Pro gating + sidebar reorg + Purchase button + free-flow counter.

## Explicitly NOT in Phase 4

| Deferred to | Item |
|---|---|
| Phase 5 | Studio's node-graph editor + replay (its sidebar "Pro" badge already exists). |
| Later / never | Hotkey-rebinding UI; privacy schedules / app blocklists; cloud sync of flows or memory; team / multi-seat licensing; recording length/count caps in Free (only the saved-flow count is gated). |
| The website/Stripe owner | Building the `mengo.ai` auth + entitlement + handoff endpoints and the Stripe checkout page. This spec only states the contract. |
| A later pass | "Claude Cowork" as a working synthesis runtime; "Bring your own LLM via MCP" as a working runtime. Both appear in the picker but are disabled ("coming soon") until concretely defined. |

## Architecture

Three new stores join `RecorderController` (Phase 2) and `FlowController` (Phase 3) as `@Observable @MainActor` singletons constructed in `MengoDesktopApp.init`:

- **`AccountStore`** — owns sign-in state + the cached entitlement. Talks to `mengo.ai` over HTTPS; stores the session token in the Keychain and the (non-secret) account metadata in a JSON cache. Exposes `plan` / `flowLimit` for gating and `state` for the hard wall.
- **`SettingsStore`** — `UserDefaults`-backed: `synthesisRuntime`, `startRecordingOnLaunch`, `openAtLogin` (the last mirrors `SMAppService.mainApp.status`; toggling it registers/unregisters the login item).
- **`SynthesisRuntime`** — an `enum` describing which CLI does synthesis, with the per-runtime command/preflight builders. `FlowController` reads `settings.synthesisRuntime` at synthesis time instead of hardcoding `claude -p`.

```
 ┌─ Mengo Desktop ─────────────────────────────────────────────────────────────┐
 │  AccountStore  ── magic-link sign-in, entitlement cache, hard wall           │
 │      │ session token → Keychain ;  {email,plan,flowLimit} → account.json     │
 │      │ HTTPS                                                                 │
 │      ▼                                                                       │
 │   mengo.ai/api/{auth/request-link, auth/exchange, me, auth/web-handoff}      │
 │                                                                              │
 │  SettingsStore ── synthesisRuntime, startRecordingOnLaunch, openAtLogin       │
 │      └─ SMAppService.mainApp.register()/.unregister()  (login item)          │
 │                                                                              │
 │  FlowController.synthesize()  ──reads──►  SettingsStore.synthesisRuntime      │
 │      ├─ .claudeCode → claude --dangerously-skip-permissions --add-dir … -p … │
 │      └─ .codex      → codex exec --dangerously-bypass-… --add-dir … -o … …   │
 │                                                                              │
 │  FlowController.save()  ──checks──►  AccountStore.plan / flowLimit  (gate)    │
 │                                                                              │
 │  MengoDesktopApp:  AccountStore.state == .signedIn  ?  MainWindowView         │
 │                                                      :  SignInView (hard wall)│
 │  .onOpenURL  ──►  mengo://auth?token=…  → AccountStore.handleAuthDeepLink     │
 │               └─  mengo://refresh        → AccountStore.refresh()             │
 └──────────────────────────────────────────────────────────────────────────────┘
```

## Components

### Account & sign-in

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/AccountStore.swift` | **new** | `@Observable @MainActor`. `enum AccountState: Equatable { case signedOut, awaitingLink(email:String), verifying, signedIn(Account) }`. `struct Account: Codable, Equatable { let email: String; let plan: Plan; let flowLimit: Int?; let validatedAt: Date }`, `enum Plan: String, Codable { case free, pro }`. `private(set) var state`. `private(set) var lastError: String?`. Methods: `sendMagicLink(email:) async` (POST `/api/auth/request-link`), `handleAuthDeepLink(token:) async` (POST `/api/auth/exchange` → store token in Keychain + account in cache → `.signedIn`), `refresh() async` (GET `/api/me` Bearer; network fail → keep cached `.signedIn`; 401 → `.signedOut` + wipe Keychain), `signOut()` (wipe Keychain + cache → `.signedOut`), `webHandoffURL(path:) async -> URL?` (POST `/api/auth/web-handoff` → append `?handoff=<code>` to `mengo.ai<path>`, for the Purchase/Manage buttons). On `init`: load token from Keychain + `account.json` → if both present `state = .signedIn(cached)` then `Task { await refresh() }`; else `.signedOut`. Honors `MENGO_DEV_ACCOUNT=pro|free` (env var) → synthetic `.signedIn` without any network. HTTP client + Keychain + clock injectable for tests. `AppDelegate.sharedAccount` bridge. `var isPro: Bool { if case .signedIn(let a) = state { a.plan == .pro } else { false } }`, `var flowLimit: Int? { … a.flowLimit … }`. |
| `Sources/MengoDesktop/MengoAPIClient.swift` | **new** | Thin HTTPS client for `mengo.ai` (`baseURL` defaults to `https://mengo.ai`, injectable). `requestLink(email:)`, `exchange(token:) -> (sessionToken:String, account:Account)`, `me(sessionToken:) -> Account`, `webHandoff(sessionToken:) -> String`. Each maps connection errors to a clear "couldn't reach mengo.ai" message and 401 to a distinct `.unauthorized`. Pure JSON decoders tested directly against canned bodies. (Reuses the lenient ISO8601 parser from `MemoryFormatting` for any timestamps.) |
| `Sources/MengoDesktop/KeychainStore.swift` | **new** | `protocol SecretStore: Sendable { func set(_ value: String, for key: String); func get(_ key: String) -> String?; func delete(_ key: String) }`. `struct KeychainStore: SecretStore` — `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` with `kSecClassGenericPassword`, service `"ai.mengo.desktop"`. Stores only the session token (key `"mengo.sessionToken"`). Tests use an in-memory stub. |
| `Sources/MengoDesktop/SignInView.swift` | **new** | The hard-wall screen rendered by `MengoDesktopApp` when `account.state != .signedIn`. States: `.signedOut` → Mengo logo, "Sign in to Mengo", email field, "Email me a link" button (disabled until a plausible email). `.awaitingLink(email)` → "Check your inbox — click the link we sent to \(email)." + "Resend" + "Use a different email". `.verifying` → spinner "Signing you in…". `lastError` shown inline. Dark/orange, hero-styled like the other panes. Takes `let account: AccountStore`. |
| `Sources/MengoDesktop/MengoURL.swift` | **new** | Pure deep-link parser. `enum MengoLink: Equatable { case auth(token: String), refresh }`. `static func parse(_ url: URL) -> MengoLink?` — `mengo://auth?token=…` → `.auth`; `mengo://refresh` → `.refresh`; anything else → `nil`. Tested directly. |

### Settings

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/SettingsStore.swift` | **new** | `@Observable @MainActor`. Persists to `UserDefaults`: `synthesisRuntime: SynthesisRuntime` (default `.claudeCode`), `startRecordingOnLaunch: Bool` (default `true`). `openAtLogin: Bool` is a computed mirror of `SMAppService.mainApp.status == .enabled`; the setter calls `register()`/`unregister()` and surfaces failures via `loginItemError: String?`. Injectable `UserDefaults` + login-item backend for tests. |
| `Sources/MengoDesktop/SynthesisRuntime.swift` | **new** | `enum SynthesisRuntime: String, Codable, CaseIterable { case claudeCode, codex, cowork, customMCP }` with `displayName` ("Claude Code", "Codex", "Claude Cowork", "Bring your own LLM (MCP)"), `isAvailable: Bool` (`.cowork`/`.customMCP` → `false`), `comingSoonNote: String?`. Plus the per-runtime build helpers (pure): given the discovered executable, the skills dir, the prompt path, and an env, return `RuntimeInvocation { executable: URL; arguments: [String]; environment: [String:String]; finalStatusSource: FinalStatusSource }` where `FinalStatusSource` is `.lastStdoutLine` (Claude) or `.file(URL)` (Codex's `-o` output). And per-runtime preflight: `.claudeCode` → `claude --version` + `claude mcp list` mentions `screenpipe`; `.codex` → `codex --version` + `codex mcp list` mentions `screenpipe` (fix command: `codex mcp add screenpipe -- npx -y screenpipe-mcp`). All pure/string-level — the process spawn itself isn't unit-tested. |
| `Sources/MengoDesktop/SettingsPane.swift` | **new** | The `.settings` pane (replaces `ComingSoonPane` for `.settings`). Dark/orange, in a `ScrollView` (mirrors `MemoryPane` so the window stays freely resizable). Sections: **Account** (email; Free/Pro badge; Free → "Upgrade to Pro" → `account.webHandoffURL(path: "/upgrade")` + "N of 3 flows used"; Pro → "Manage account" → `account.webHandoffURL(path: "/account")`; "Sign out"; "Refresh now"); **Synthesis model** (a `Picker`/radio list over `SynthesisRuntime.allCases`, disabled rows show the `comingSoonNote`; caption explaining Claude Code/Codex are auto-configured and the screenpipe MCP is wired into whichever is picked); **Startup** (Toggle "Open Mengo Desktop at login" bound to `settings.openAtLogin`; Toggle "Start recording when Mengo opens" bound to `settings.startRecordingOnLaunch`); **Logs & data** ("Open recorder log" → `recorder.recorderLogURL`; "Open Flow log" → the `flow.log` in `Log.directory`; "Reveal recordings folder" → `recorder.dataFolderURL`; "Reveal Mengo data folder" → `~/Library/Application Support/MengoDesktop`). Takes `account`, `settings`, `recorder`, `flow`. |

### Gating & sidebar

| File | Status | Change |
|---|---|---|
| `Sources/MengoDesktop/FlowController.swift` | modify | (1) Inject `account: AccountStore` (weak) + `settings: SettingsStore`. (2) `save(...)` — before finalizing, if `!account.isPro` and the count of *existing* Library flows ≥ `account.flowLimit ?? .max`, do **not** save; instead `onFlowLimitReached()` (default presents an NSAlert with **Upgrade** → opens the web upgrade page → and **Cancel**; stays in `.reviewing`). (3) `synthesize()` — replace the hardcoded `claude -p` build with `SynthesisRuntime` dispatch on `settings.synthesisRuntime`: discover the runtime's executable (`findClaude()` / new `findCodex()`), build the `RuntimeInvocation`, run it, then read the final status from `.lastStdoutLine` or `.file(url)` per the invocation. (4) `preflight()` — runtime-aware: run the selected runtime's preflight; the `.claudeNotFound`/`.claudeMCPNotConfigured` cases generalize to `.runtimeNotFound(SynthesisRuntime)` / `.runtimeMCPNotConfigured(SynthesisRuntime)` with the right install/`mcp add` message. |
| `Sources/MengoDesktop/MainWindowView.swift` | modify | Sidebar: render Memory/Flow/Library/Studio at the top, then `Spacer()`, then — *only when `!account.isPro`* — a **"Purchase Mengo Pro"** button (orange/prominent → opens `account.webHandoffURL(path:"/upgrade")`) and a caption "`N` of 3 free flows used" (`N = flow.library.filter(\.exists).count`), then the **Settings** row pinned at the bottom. Takes `account` + `flow` in addition to what it already takes. |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | modify | Construct `AccountStore`, `SettingsStore`; pass into `MainWindowView`/`MenuBarContent`/`FlowController.live`/`SettingsPane`. `WindowGroup`/`Window` body: `if case .signedIn = account.state { MainWindowView(…) } else { SignInView(account:) }`. `.onOpenURL { url in if let link = MengoURL.parse(url) { handle… } }`. `applicationDidFinishLaunching`: only `recorder.start()` when signed in **and** `settings.startRecordingOnLaunch` (and start it on the sign-in→signedIn transition too); always `account.refresh()` if a cached session exists. |
| `Sources/MengoDesktop/MenuBarContent.swift` | modify | When `account.state != .signedIn` → the menu shows just "Sign in to Mengo Desktop…" (→ raises the main window) + Quit; everything else hidden. When signed in → as today, plus (Free only) an "Upgrade to Mengo Pro…" item near Settings. |
| `Sources/MengoDesktop/SidebarSection.swift` | modify | `phase` for `.settings` stays `4`; update `comingSoonBlurb` is moot (no longer placeholdered). No new cases. (Settings is already last in `allCases`.) |
| `Resources/MengoDesktopInfo.plist` | modify | Add `CFBundleURLTypes` with scheme `mengo`. Add `NSAppTransportSecurity` exception is unnecessary (`mengo.ai` is HTTPS); keep the existing `NSAllowsLocalNetworking` for `127.0.0.1:3030`. |
| `build-mengo.sh` | confirm | No new copy steps. Note: `SMAppService.mainApp.register()` wants a properly-signed app in a standard location — works with the stable dev cert (`bootstrap-cert.sh`) and an install under `~/Applications/`; flag in the smoke checklist that an ad-hoc-signed build may not toggle the login item. |

(`AppState` keeps just `selectedSection` — account/settings live in their own stores.)

## Data formats & the mengo.ai contract

**Local:**
- Keychain (`kSecClassGenericPassword`, service `ai.mengo.desktop`, account `mengo.sessionToken`): the opaque session token string.
- `~/Library/Application Support/MengoDesktop/account.json`: `{ "email": "...", "plan": "free"|"pro", "flowLimit": 3|null, "validatedAt": "<ISO8601>" }` — a non-secret cache so launches work offline.
- `UserDefaults`: `synthesisRuntime` (`"claudeCode"`…), `startRecordingOnLaunch` (`Bool`). (`openAtLogin` is not persisted by us — `SMAppService` is the source of truth.)

**mengo.ai endpoints the app calls** (the website/Stripe owner builds these):
- `POST /api/auth/request-link` — body `{ "email": "..." }` → `200 { "ok": true }`. Emails the user a link `mengo://auth?token=<single-use, short-lived>`.
- `POST /api/auth/exchange` — body `{ "token": "<from the email>" }` → `200 { "sessionToken": "...", "account": { "email": "...", "plan": "...", "flowLimit": ... } }`; bad/expired token → `401`.
- `GET /api/me` — `Authorization: Bearer <sessionToken>` → `200 { "email": "...", "plan": "...", "flowLimit": ... }`; revoked session → `401`.
- `POST /api/auth/web-handoff` — `Authorization: Bearer <sessionToken>` → `200 { "handoffCode": "<single-use, short-lived>" }`. The app opens `https://mengo.ai/upgrade?handoff=<code>` (Stripe checkout) or `https://mengo.ai/account?handoff=<code>` (manage); the web page exchanges the code for a logged-in web session.
- *(optional)* `POST /api/auth/signout` — `Authorization: Bearer <sessionToken>` → invalidates it server-side.

**Deep links the app handles** (registered `mengo://` scheme): `mengo://auth?token=…` (the magic link); `mengo://refresh` (the web fires this after a successful Stripe purchase so the app re-validates and flips to Pro immediately, without waiting for the daily `refresh()`).

**`flow.json` / `SKILL.md` / synthesis-prompt** — unchanged from Phase 3; Codex gets the same prompt (path-parameterized via `$MANIFEST_PATH`), and the `{"status":"ok",…}` / `{"status":"error",…}` final-line contract is the same — for Codex we read it from the `--output-last-message` file rather than scanning stdout.

## Error handling

- **Sign-in:** `request-link` network fail → `lastError = "Couldn't reach mengo.ai — check your connection."`, stays `.signedOut`. `exchange` 401 (bad/expired link) → `lastError = "That link has expired — request a new one."`, back to `.signedOut`. The magic link is single-use; clicking it twice is a 401 the second time (acceptable).
- **Refresh while signed in:** network fail → silently keep the cached `.signedIn` (offline-tolerant; the cached `validatedAt` ages but nothing breaks). 401 (session revoked/expired) → `.signedOut`, wipe Keychain + cache, the hard wall reappears.
- **Hard wall before the website auth exists:** without `MENGO_DEV_ACCOUNT` set and with no cached session, the app sits on the sign-in screen and `request-link` will fail (no server) — expected; `MENGO_DEV_ACCOUNT=pro` is the dev path until the website ships.
- **Flow-limit gate:** at the limit, `save()` shows the upgrade alert and stays in `.reviewing` (the recording isn't lost — they can delete an old flow then Save). Pro and under-limit users are unaffected.
- **Runtime preflight:** the selected runtime's binary not on PATH → "`<Runtime>` CLI not found — install it, then retry." (the message names the runtime and where it looked). The runtime's MCP missing `screenpipe` → shows the exact `… mcp add screenpipe …` for that runtime, with a [Copy] button. Picking a disabled runtime is impossible (the picker disables it); if `settings.synthesisRuntime` is somehow `.cowork`/`.customMCP` (e.g. stale defaults), preflight fails with "`<Runtime>` isn't available yet — pick Claude Code or Codex in Settings."
- **`SMAppService` register failure** (unsigned/relocated app) → `settings.loginItemError` shows "Couldn't register the login item — move Mengo Desktop to Applications and try again."; the toggle reverts.
- **Bad deep link** (`mengo://something-else`) → ignored (logged, no crash).

## Testing

**Swift unit tests:**
- `AccountStore`: `init` with a cached session+account → `.signedIn`; without → `.signedOut`. `sendMagicLink` → `.awaitingLink`; on network fail → stays `.signedOut` + `lastError`. `handleAuthDeepLink` (stub HTTP returns `{sessionToken,account}`) → `.signedIn`, token written to the stub Keychain, account cached. `refresh` with stub returning Pro → plan updates + re-cached; with stub throwing a connection error → stays `.signedIn(cached)`; with stub returning 401 → `.signedOut` + Keychain wiped. `signOut` → `.signedOut` + Keychain/cache cleared. `MENGO_DEV_ACCOUNT=pro` → `.signedIn` with a synthetic Pro account, no HTTP calls. (Stub HTTP client, stub `SecretStore`, injected clock.)
- `MengoAPIClient`: pure decoders — `exchange`/`me` parse canned bodies (incl. `flowLimit: null` for Pro); a 401 response surfaces as `.unauthorized`; a connection error surfaces as the "couldn't reach mengo.ai" message.
- `KeychainStore`: round-trip via the in-memory stub (set → get → delete → get == nil). (The real `SecItem*` path isn't unit-tested.)
- `MengoURL.parse`: `mengo://auth?token=abc` → `.auth("abc")`; `mengo://refresh` → `.refresh`; `mengo://auth` (no token) → `nil`; `https://…` → `nil`; garbage → `nil`.
- `SettingsStore`: `synthesisRuntime` and `startRecordingOnLaunch` persist across instances (injected `UserDefaults`). `openAtLogin` setter calls register/unregister on the stub backend and reflects its state; a stub failure → `loginItemError` set, value reverts.
- `SynthesisRuntime`: `displayName`/`isAvailable`/`comingSoonNote` per case. The per-runtime invocation builders — `.claudeCode` → expected `claude` args + `finalStatusSource == .lastStdoutLine`; `.codex` → expected `codex exec …` args incl. `-o <file>` + `finalStatusSource == .file(file)`. Per-runtime preflight string checks (given a fake `mcp list` output with/without `screenpipe`).
- `FlowController` gating: with a stub `AccountStore` at Free + `flowLimit 3` and a Library already holding 3 existing flows, `save(...)` does **not** add a 4th and stays `.reviewing` (and calls `onFlowLimitReached`); with `flowLimit 3` and 2 flows, or with Pro, `save` proceeds as today. Extend `FlowControllerTests`' `makeController` with `account:`/`plan:`/`flowLimit:` params and a `SettingsStore` (defaulting to `.claudeCode`, so existing synthesis tests are unchanged). `synthesize()` with `settings.synthesisRuntime == .codex` and a stub spawner → asserts a `codex exec` command was issued (the existing `.claudeCode` tests still pass unchanged).
- Existing `RecorderControllerTests` etc. keep passing (no behavior change to Memory beyond the launch-time `start()` now being conditional on sign-in + `startRecordingOnLaunch`; cover that path).

**No SwiftUI view tests** (none in this repo) — `SignInView`, `SettingsPane`, the sidebar Purchase block, and the menu-bar signed-out state are covered by:

**Manual smoke checklist** `docs/manual-smoke-tests/mengo-phase-4-account-licensing.md`:
- Cold launch with no cached session → the sign-in hard wall (no sidebar/Memory). `MENGO_DEV_ACCOUNT=pro` → app opens straight to Memory, signed-in as Pro; Settings → Account shows Pro, no Purchase button in the sidebar.
- `MENGO_DEV_ACCOUNT=free` → Settings → Account shows Free + "0 of 3 flows used"; the sidebar shows "Purchase Mengo Pro" + the counter above Settings; Settings sits at the bottom of the sidebar. Record/save 3 flows → the counter ticks to "3 of 3"; recording + Save a 4th → the "Upgrade to keep more flows" alert; **Cancel** → stays in Review, nothing lost; delete one from the Library → Save the held flow → it lands, counter back to "3 of 3".
- Settings → Synthesis model: Claude Code is the default; pick Codex → record a real task → synthesis runs via `codex exec` (check `~/.codex` got `screenpipe` MCP wired, or the preflight told you to run `codex mcp add screenpipe …`) → Review shows a sensible skill → Save. Switch back to Claude Code → still works. Claude Cowork and "Bring your own LLM (MCP)" are visible but disabled with a "coming soon" note.
- Settings → Startup: toggle "Open Mengo Desktop at login" on → confirm it appears in System Settings › General › Login Items; toggle off → gone. Toggle "Start recording when Mengo opens" off → quit → relaunch → the recorder stays idle until you start it from the Memory pane; toggle on → relaunch → it auto-starts.
- Settings → Logs & data: each of the four buttons opens/reveals the right file/folder.
- Sign out (Settings → Account) → the hard wall reappears, the recorder stops; `MENGO_DEV_ACCOUNT` re-grants access on next launch.
- Deep links: `open "mengo://refresh"` while running → `account.refresh()` fires (no-op if offline, fine); `open "mengo://auth?token=abc"` → exercises `handleAuthDeepLink` (will 401 against a real-but-empty server — expected). `open "mengo://garbage"` → no crash.
- Build + `swift test` green; `./build-mengo.sh` produces `MengoDesktop.app` that codesigns cleanly and registers the `mengo://` scheme (`open "mengo://refresh"` reaches the app).

**The mengo.ai endpoints / Stripe checkout are out of scope** — the manual checklist's account paths use `MENGO_DEV_ACCOUNT` until the website ships them.

## Open questions for the implementation plan

- **`findCodex()` locations** — mirror `findClaude()`: `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `~/.local/bin/codex`, `~/bin/codex` (the local box has `/opt/homebrew/bin/codex` — confirm the list during the plan).
- **Codex MCP wiring** — should Mengo *auto-run* `codex mcp add screenpipe -- npx -y screenpipe-mcp` on first Codex use (like nothing today auto-configures Claude's MCP), or only surface the command in the preflight alert? Lean: surface it (consistent with the Claude Code path); revisit if it's a friction point.
- **`flowLimit` source of truth** — the app reads it from `/api/me`'s `flowLimit` (so the limit is server-configurable), defaulting to `3` if the field is absent on a Free account and `nil`/unlimited on Pro. Confirm the contract field name with the website owner when they build it.
- **Sign-in screen vs. sheet** — a full-window replacement (`SignInView` instead of `MainWindowView`) is cleaner than a sheet for a hard wall; confirm in the plan. The `MenuBarExtra` stays present but minimal (just "Sign in…").
- **`SMAppService` minimum** — `SMAppService.mainApp` is macOS 13+ (fine; the app targets 15+); just confirm the entitlement story (it needs none beyond being a signed app the system trusts).
- **Where the upgrade/manage URLs point** — `https://mengo.ai/upgrade` and `https://mengo.ai/account` with `?handoff=<code>`; if the website owner picks different paths, it's a one-line change. The `?handoff=` query is a single-use short-lived code (not the session token) so it's safe to put in a URL.
