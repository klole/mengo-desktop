# Mengo Desktop V1 Release and Codex for OSS Application Plan

Date: 2026-07-08

This plan is scoped to getting Mengo Desktop to a credible V1 release state and making the GitHub repository strong enough to use for an OpenAI Codex for Open Source application.

## Progress Log

### 2026-07-08 implementation pass

Completed or improved:

- Rewrote public README around Mengo Desktop.
- Rewrote `install.sh` to install `MengoDesktop.app`.
- Rewrote `CLAUDE.md` for Mengo Desktop agent setup.
- Added `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, GitHub issue templates, PR template, and macOS CI skeleton.
- Added `docs/roadmap.md` and `docs/manual-smoke-tests/mengo-v1.md`.
- Renamed Swift package identity to `MengoDesktop` while keeping legacy targets for now.
- Fixed full `swift test` determinism by isolating legacy ScreenpipeFlow library tests from the real `~/.claude/skills`.
- Declared Mengo test fixtures as SwiftPM resources.
- Fixed a Swift 6 actor-isolation warning in Mengo manifest tests.
- Added app-level sign-out routing that cancels active Flow UI, stops the recorder, clears account state, and returns to Memory.
- Wired `AppDelegate.sharedAccount` and `sharedSettings` so launch/recovery gates can see account state.
- Gated interrupted-recording recovery prompts behind signed-in state.
- Persisted Review edits to `SKILL.md` and `flow.json`.
- Made source catalog subprocess failures throw on nonzero exit.
- Made recorder `start()` idempotent to avoid duplicate helper processes.
- Surfaced global hotkey registration failure through `FlowController.hotkeyNote`.
- Changed release packaging to produce an architecture-specific `MengoDesktop-macos-arm64.zip` on this machine instead of falsely implying a universal helper.
- Added first-class local preview mode so OSS users can run without hosted account endpoints.
- Updated public GitHub description/topics and opened V1 roadmap issues #1-#7.
- Opened draft PR: https://github.com/klole/mengo-desktop/pull/8
- Fixed legacy ScreenpipeMenu CI build compatibility on Xcode 16.4.
- Moved the ScreenpipeFlow synthesis prompt into a target-local SwiftPM resource path while keeping the app-bundle resource for Mengo Desktop packaging.
- Fixed Swift 6 XCTest actor-isolation issues in legacy manifest writer tests.
- Added `scripts/notarize-mengo.sh` and `MENGO_SIGN_FOR_NOTARIZATION=1` packaging support for Developer ID hardened-runtime signing plus Apple notarization.
- Added `scripts/smoke-codex-runtime.sh` for repeatable Codex CLI/MCP/final-message smoke testing.
- Added `scripts/release-readiness-status.sh` for repeatable terminal release-gate checks.
- Verified `@screenpipe/cli-darwin-x64` package availability in npm, but documented the preview release as Apple Silicon-only until an Intel-built artifact is smoke-tested on Intel hardware.
- Prepared a draft `v0.1.0-preview` prerelease with `MengoDesktop-macos-arm64.zip` attached; it remains unpublished.
- Fixed the in-app Codex smoke failure where Codex reported the parent skills directory plus a slug, causing Review to look for `SKILL.md` in the parent directory.
- Fixed Library's "Re-open in Review" action so it navigates back to Flow after opening a saved skill for review.
- Added unit coverage for Codex MCP preflight with both missing-`screenpipe` and configured-`screenpipe` MCP output.
- Prepared copy-ready Codex for OSS application notes with sub-500-character form answers.

Current verification:

- `swift test` passed: 189 tests, 0 failures.
- `./build-mengo.sh` passed.
- `codesign --verify --deep --strict --verbose=2 MengoDesktop.app` passed.
- `MengoDesktop.app/Contents/MacOS/MengoDesktop` and `Contents/Helpers/screenpipe` both report `arm64` in the latest local artifact.
- `spctl --assess --type execute -vv MengoDesktop.app` still rejects the app because the build is ad-hoc/self-signed and not notarized.
- GitHub Actions macOS `build-test` passes on the V1 readiness PR.
- Current local keychain has an Apple Development signing identity only; Developer ID Application certificate and notarytool credentials are still required to complete notarization.
- Codex CLI scripted preflight passes locally after adding `screenpipe` MCP: `codex-cli 0.143.0`, `codex mcp list` includes `screenpipe`, and `codex exec --output-last-message` writes the final JSON line Mengo parses.
- Codex scripted negative smoke passes: `MENGO_CODEX_SMOKE_NEGATIVE=missing-mcp scripts/smoke-codex-runtime.sh` simulates a missing screenpipe MCP and verifies the setup command is printed.
- Local in-app Codex smoke passed through record -> synthesize -> review -> persist: Codex generated `~/.claude/skills/record-mengo-flow-skill/`, Review loaded `SKILL.md` from the slug directory, and the library entry persisted `file:///Users/kylebell/.claude/skills/record-mengo-flow-skill/`.
- Local Library -> Review -> Save UI smoke passed on the generated Codex skill: reopening from Library navigated to Flow review, Save exited review back to Flow idle, and the library entry stayed pointed at the slug directory.
- `scripts/release-readiness-status.sh` passes on branch `v1-release-readiness`: local tests, codesign, checksum, expected non-notarized Gatekeeper rejection, Codex positive/negative smoke, PR status, and draft release asset digest are green.
- Clean-account scripted check passes: `HOME=$(mktemp -d) swift test` completed with 186 tests, 0 failures.
- Architecture support status: `build-mengo.sh` supports host-specific `arm64` and `x86_64` packaging; the current local artifact and preview notes are Apple Silicon-only because Intel hardware smoke is still missing.
- Latest local release asset checksum and draft release asset digest: `sha256:e4d3b21192ac76d1e68aca0cfde4243464f071a4787b8572fd1fe93739c054bd`.
- One full `swift test` run transiently hung once, then the suspected focused test and a second full run passed. Watch for recurrence.

Still open:

- Developer ID signing and notarization.
- Hosted account strategy beyond local preview mode.
- Broken-Codex setup manual GUI alert smoke.
- Manual app smoke matrix on a clean user account.
- Legacy target strategy after V1: keep legacy targets in the package for the preview because full CI is now green, then move or remove if they continue to create maintenance noise.

The relevant application signals are:

- The repository must be public and tied to a visible GitHub username.
- The applicant should be a primary or core maintainer.
- The project should show meaningful usage, broad adoption, or clear importance to the software ecosystem.
- The repo should show evidence of active maintenance: issue triage, releases, review, security posture, and ongoing maintainer workflows.
- The application asks for concise answers about why the repo qualifies and how API credits would support core OSS work.

## Executive Readiness Call

Mengo Desktop is the best candidate in this workspace, but it is not application-ready as-is.

The strong case is conceptually good: Mengo Desktop records local screen/audio context, turns demonstrated workflows into reusable Codex/Claude-style skills, and sits close to the maintainer automation story OpenAI says the program supports. The weak case is public evidence: the repo currently looks like a renamed private/experimental project, has stale ScreenpipeMenu branding, lacks a license/security/contribution posture, has no visible issue/PR activity, has no public adoption signals, and the latest public release asset still appears to be named for the old app.

The practical target is not "perfect commercial app." The target is a clean OSS V1 that:

- installs and runs predictably on a supported macOS range,
- has one compelling working loop: record a task, synthesize a skill, review it, save it, run it,
- is honest about local-first privacy and current limitations,
- has public docs that match the product,
- has passing CI and reproducible release steps,
- has a visible roadmap and contribution/security posture,
- can credibly explain why Codex credits would improve maintainer workflows.

## V1 Definition

V1 should mean:

- A public macOS app named Mengo Desktop.
- Primary flows: Memory, Flow, Library, Settings, Account/preview gating.
- One supported runtime path works end to end: Codex or Claude Code. Prefer making Codex first-class for the application story, while keeping Claude Code supported if already stable.
- App can record, pause/resume, search local memory, create a workflow skill, review it, save it under the expected skills directory, and delete it.
- Release artifact is signed well enough for target users. Notarization is strongly preferred before calling it V1.
- Public repo has OSS basics: license, README, contributing docs, security policy, issue templates, release notes, CI.
- Known V1 limitations are documented instead of hidden.

V1 should not require:

- The Studio section to be fully built.
- Paid Stripe billing to be live.
- A full cloud account backend, unless the app is marketed as requiring hosted accounts.
- Cross-platform support.
- A polished website, except enough landing/docs content to explain the app and link the repo/release.

## Current Baseline

Observed repo state:

- Local repo: `/Users/kylebell/screenpipe.old`
- Public remote: `https://github.com/klole/mengo-desktop.git`
- Default branch: `main`
- Main app target exists under `Sources/MengoDesktop`
- Legacy targets still exist: `Sources/ScreenpipeMenu`, `Sources/ScreenpipeFlow`
- Current `Package.swift` package name is still `ScreenpipeMenu`
- `README.md`, `CLAUDE.md`, `install.sh`, and some release/install copy still reference ScreenpipeMenu or `screenpipe-menu`
- No `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, or `.github` issue templates were found
- Built artifacts exist in the worktree: `MengoDesktop.app`, `MengoDesktop.zip`, `ScreenpipeMenu.app`, `ScreenpipeMenu.zip`
- `.DS_Store` files exist under source/test paths and should not be versioned
- `.claude/` is currently untracked and should be checked before any commit

Observed verification from the audit:

- `swift test --filter MengoDesktopTests` passed: 133 selected tests, 0 failures
- Full `swift test` failed in legacy `ScreenpipeFlowTests.AppStateTests`, not in MengoDesktop tests
- `swift build` passed, but warned about an unhandled fixture: `Tests/MengoDesktopTests/Fixtures/health-ok.json`
- `./build-mengo.sh` passed and produced `MengoDesktop.app` plus `MengoDesktop.zip`
- `codesign --verify --deep --strict --verbose=2 MengoDesktop.app` passed
- `spctl --assess --type execute -vv MengoDesktop.app` rejected the app because it is signed with a local self-signed development certificate
- MengoDesktop binary is universal, but the embedded `screenpipe` helper built on this machine appears host-arch-specific

## Track A: Public Repo Identity and OSS Readiness

### A1. Fix the project identity everywhere

Problem:

The public repo must look like Mengo Desktop, not an unfinished ScreenpipeMenu rename.

Tasks:

- Rename the Swift package in `Package.swift` from `ScreenpipeMenu` to `MengoDesktop`, or split legacy packages if preserving old targets.
- Decide whether legacy targets remain in the package. Recommended V1 path: keep only the MengoDesktop product in the default build/test path and move legacy ScreenpipeMenu/ScreenpipeFlow to a `Legacy/` folder or remove after tagging an archive branch.
- Rewrite `README.md` around Mengo Desktop:
  - one-line product description,
  - what it does,
  - local-first privacy model,
  - exact supported macOS versions,
  - install instructions,
  - build instructions,
  - runtime prerequisites,
  - permissions required,
  - troubleshooting,
  - current limitations,
  - screenshots or GIFs.
- Rewrite `CLAUDE.md` or replace it with `AGENTS.md`/maintainer instructions that match Mengo Desktop.
- Rewrite `install.sh` so it installs `MengoDesktop.app`, not `ScreenpipeMenu.app`.
- Replace release copy that says `ScreenpipeMenu.zip`.
- Search and remove stale references:
  - `screenpipe-menu`
  - `ScreenpipeMenu`
  - old GitHub URLs
  - old app bundle identifiers where inappropriate
  - old log paths where inappropriate
- Keep technical references to screenpipe where they are accurate: screenpipe is still the recorder engine.

Acceptance criteria:

- `rg "ScreenpipeMenu|screenpipe-menu" README.md CLAUDE.md install.sh Package.swift docs Sources/MengoDesktop Resources` returns only intentional legacy/source attribution references.
- GitHub repo front page explains Mengo Desktop in the first viewport.
- A user following the README can install or build Mengo Desktop without knowing the project history.

### A2. Add basic OSS governance files

Problem:

The Codex for OSS application is about maintainership. The repo needs to look maintainable.

Tasks:

- Add `LICENSE`. Recommended: MIT if the goal is adoption and permissive reuse. Use a different license only if there is a real strategic reason.
- Add `SECURITY.md`:
  - where to report vulnerabilities,
  - supported versions,
  - local recorder/privacy threat model,
  - no public security issue disclosure until triaged.
- Add `CONTRIBUTING.md`:
  - local setup,
  - build/test commands,
  - release process overview,
  - coding conventions,
  - how to add tests,
  - how to file issues.
- Add `CODE_OF_CONDUCT.md` if you want conventional OSS expectations.
- Add `.github/ISSUE_TEMPLATE/bug_report.yml`.
- Add `.github/ISSUE_TEMPLATE/feature_request.yml`.
- Add `.github/PULL_REQUEST_TEMPLATE.md`.
- Add `.github/dependabot.yml` if package/dependency automation is useful.
- Add repo topics on GitHub:
  - `macos`
  - `swift`
  - `swiftui`
  - `screenpipe`
  - `codex`
  - `claude-code`
  - `skills`
  - `workflow-automation`
  - `local-first`

Acceptance criteria:

- Public repo has visible license and security policy.
- New contributors can run tests and understand what changes are welcome.
- GitHub issue creation guides users into actionable reports.

### A3. Establish visible active maintenance

Problem:

The repo has weak public activity signals. A polished release alone is less convincing than an actively maintained project.

Tasks:

- Open GitHub issues for the real roadmap instead of keeping it only in private docs:
  - "V1: repo identity cleanup"
  - "V1: signing and notarization"
  - "V1: Codex runtime smoke test"
  - "V1: account mode decision"
  - "V1: review edits persist to SKILL.md"
  - "V1: source picker robustness"
  - "Post-V1: Studio"
- Tag issues with labels: `v1`, `good first issue`, `docs`, `bug`, `security`, `release`, `runtime`.
- Convert the most useful parts of this plan into a public roadmap issue or `docs/roadmap.md`.
- Create at least one PR for the cleanup work, even if self-authored, so the repo demonstrates review/maintenance workflow.
- Create release notes for V1 and an upgrade note from older ScreenpipeMenu builds if needed.

Acceptance criteria:

- Repo has recent issues, labels, and at least one merged PR showing active maintenance.
- Release notes describe what changed and what is next.
- The application can point to public evidence of active maintainer work.

## Track B: Source Tree and Build Hygiene

### B1. Decide legacy target strategy

Problem:

The current package mixes Mengo Desktop with legacy ScreenpipeMenu and ScreenpipeFlow. This is causing full test failures and branding confusion.

Recommended decision:

- Treat Mengo Desktop as the sole V1 product.
- Preserve legacy code only if it helps migration or historical context.
- Do not let legacy tests block Mengo Desktop CI.

Options:

- Option 1: Move legacy targets to `Legacy/` and remove them from default `Package.swift`.
- Option 2: Keep legacy targets, but mark legacy tests isolated and fix their home-directory dependence.
- Option 3: Delete legacy targets after tagging a pre-cleanup archive branch.

Recommended V1 path:

- Option 1 first, then delete later only after V1 is stable.

Tasks:

- Update `Package.swift` so default products and tests focus on MengoDesktop.
- Ensure `swift build` builds the intended app target.
- Ensure `swift test` either runs all relevant V1 tests or makes legacy exclusion explicit.
- Move old manual smoke docs to `docs/legacy/` if they are not applicable to Mengo Desktop.

Acceptance criteria:

- `swift test` is green from a clean checkout.
- No failing tests depend on the developer's real `~/.claude/skills`.
- CI command matches the documented local command.

### B2. Fix test isolation

Problem:

Full test suite failed because legacy `ScreenpipeFlowTests.AppStateTests` scanned the real local `~/.claude/skills` and found a real skill.

Tasks:

- Refactor legacy `AppState` tests to inject a temp skills directory, or remove legacy tests from V1 package.
- Audit MengoDesktop tests for any reads from:
  - `~/.claude`
  - `~/Library/Application Support`
  - `~/Library/Logs`
  - real Keychain
  - real UserDefaults suite
- Ensure every test uses temp dirs or isolated stores.
- Add regression tests for library scanning and account state.

Acceptance criteria:

- `swift test` passes on a clean machine and on the current developer machine.
- Running tests does not create, delete, or read personal skills outside temp directories.

### B3. Clean build warnings and repo noise

Tasks:

- Add or explicitly process `Tests/MengoDesktopTests/Fixtures/health-ok.json` so SwiftPM warning disappears.
- Remove `.DS_Store` files from tracked/untracked source/test paths.
- Add `.gitignore` entries for:
  - `.DS_Store`
  - `.build/`
  - `*.app`
  - `*.zip`
  - derived release artifacts
  - local `.claude/` unless intentionally needed
- Confirm no secrets, API tokens, or user-local paths are in the repo.

Acceptance criteria:

- `git status --short` is clean after build/test except intentional source changes.
- `swift build` has no avoidable warnings.

### B4. Add CI

Problem:

The public repo needs objective proof that the app builds and tests.

Tasks:

- Add GitHub Actions workflow for macOS:
  - checkout,
  - select supported Xcode version if needed,
  - `swift build`,
  - `swift test`,
  - optional `./build-mengo.sh --ci` if made noninteractive.
- Add caching only after basic CI is stable.
- Make release packaging a separate manual workflow later if notarization credentials are available.

Acceptance criteria:

- CI passes on `main`.
- README badge shows build/test health.

## Track C: Product V1 Blockers

### C1. Sign-out must stop recording

Problem:

`SettingsPane` calls `account.signOut()`, but `AccountStore.signOut()` only clears account state. Recorder shutdown appears tied mainly to app termination. That means signing out may leave recording active behind an access wall.

Tasks:

- Route sign-out through app-level state instead of calling only `AccountStore`.
- On sign-out:
  - stop recorder,
  - stop in-progress flow recording,
  - clear sensitive account cache,
  - return to signed-out view,
  - make menu state reflect stopped/locked state.
- Add tests:
  - sign-out calls recorder stop,
  - sign-out from recording state stops recording,
  - sign-out from synthesizing/review state does not delete unsaved skill output unless explicitly confirmed.

Acceptance criteria:

- Manual test: start recording, sign out, verify screenpipe process stops and UI no longer claims recording.
- Unit tests cover sign-out side effects.

### C2. Decide the account/auth V1 story

Problem:

Account code assumes hosted `mengo.ai` endpoints, while current usable local path is `MENGO_DEV_ACCOUNT=pro|free`. A public V1 cannot require nonexistent backend behavior.

Decision needed:

- V1 Preview: no hosted account required; local preview mode is documented.
- V1 Hosted: real `mengo.ai` auth endpoints are live and tested.

Recommended V1 path:

- Ship as "developer preview" or "local OSS preview" with no hosted account requirement.
- Remove hard product gating that makes the app unusable without a backend, or provide a clear local unlock mode.
- Keep account UI honest: "Hosted account support is not available in this OSS preview" if backend is not live.

Current implementation:

- Local preview mode is available from the sign-in screen.
- `MENGO_PREVIEW_ACCOUNT=pro|free` starts local preview for smoke tests.
- `MENGO_DEV_ACCOUNT=pro|free` remains accepted as a legacy alias.
- Hosted magic-link code remains present, but V1 OSS preview does not depend on it.

Tasks:

- Audit `AccountStore`, `MengoAPIClient`, `SignInView`, `SettingsPane`, and gating logic.
- Decide whether free/pro limits apply in OSS V1.
- If using preview mode:
  - document `MENGO_DEV_ACCOUNT=pro` clearly,
  - rename it if public-facing, e.g. `MENGO_PREVIEW_ACCOUNT=pro`,
  - avoid shipping confusing "Sign in with mengo.ai" if it cannot work.
- If using hosted auth:
  - implement endpoint contracts,
  - document account deletion/privacy,
  - add integration tests or mocked contract tests.

Acceptance criteria:

- A new user can run the app from README instructions without hitting a dead sign-in screen.
- Account UI text matches reality.
- Free/pro gates cannot cause data loss.

### C3. Make review edits actually persist

Problem:

`SkillReviewView` exposes editable name/description/parameters, but `FlowController.save(...)` notes that in-place `SKILL.md` rewrite is a follow-up. That is a V1 trust problem: the UI promises edits that are not fully saved.

Tasks:

- Parse the generated `SKILL.md` frontmatter/sections using a structured path where possible.
- Persist edited:
  - display name,
  - slug,
  - short description,
  - parameters,
  - parameter descriptions/defaults if present.
- Update `flow.json` or index metadata if it stores duplicate fields.
- Ensure rename behavior updates directory slug safely.
- Preserve unknown markdown content.
- Add tests for:
  - edit description then save,
  - edit parameter then save,
  - rename to existing slug creates unique slug or blocks cleanly,
  - invalid slug characters are normalized,
  - save failure leaves the review state recoverable.

Acceptance criteria:

- Manual test: synthesize a skill, edit name/description/parameters, save, reopen file in `~/.claude/skills/<slug>/SKILL.md`, verify edits are present.
- Library display matches saved file.

### C4. Codex runtime must be first-class, or clearly not V1

Problem:

The app contains `SynthesisRuntime.codex`, but much of the product copy still says Claude Code. For the Codex for OSS application, Codex support should be real, tested, and easy to explain.

Tasks:

- Decide default runtime:
  - If Codex is stable: make Codex the preferred/default runtime.
  - If Claude Code is currently more stable: keep Claude default, but make Codex beta explicit.
- Audit runtime copy in:
  - `FlowPane`
  - `SettingsPane`
  - `SidebarSection`
  - manual smoke tests
  - README
  - synthesis prompt
- Add runtime-specific preflight:
  - executable found,
  - MCP screenpipe configured if needed,
  - output directory writable,
  - sensitive path permissions handled,
  - clear install command for missing runtime.
- Smoke test actual Codex invocation with a short recording.
- Update tests for Codex command construction and failure messaging.

Acceptance criteria:

- A user can choose Codex in Settings and complete record -> synthesize -> review -> save.
- Failure states say "Codex" when Codex fails and "Claude Code" when Claude fails.
- The README can truthfully say Mengo supports Codex.

### C5. Memory source picker and recorder source hardening

Problem:

Recording source selection is important for trust. Process failure handling and helper process status need hardening.

Tasks:

- Ensure `ScreenpipeCLICatalog.runJSON` checks process termination status, not just JSON parse success.
- Show actionable errors when source enumeration fails.
- Handle missing screenpipe helper.
- Handle screen recording permission denied.
- Handle microphone permission denied.
- Handle no displays/audio devices.
- Add tests around failed CLI exit, invalid JSON, empty source lists, and partial device data.

Acceptance criteria:

- Manual test: block permissions or break helper path and verify user-facing error is understandable.
- Source picker never silently shows stale or fake data after a command failure.

### C6. Recorder lifecycle hardening

Problem:

Recorder start behavior is documented as safe/idempotent, but duplicate spawn prevention needs to be proven.

Tasks:

- Add a non-idle guard in `RecorderController.start()` if missing.
- Ensure rapid start/pause/resume/stop cannot spawn duplicate screenpipe processes.
- Ensure termination cleanup reaps processes.
- Ensure app relaunch handles stale recorder process correctly.
- Add tests for:
  - double start,
  - start while starting,
  - pause while stopped,
  - stop while already stopped,
  - process crash recovery.

Acceptance criteria:

- Manual test with Activity Monitor/process list shows at most one bundled screenpipe helper per app session.
- UI status always matches process state within a short polling interval.

### C7. Recovery prompts and locked state

Problem:

Recovery prompts may appear regardless of signed-in/signed-out state. This can expose confusing or inappropriate actions.

Tasks:

- Gate recovery prompts behind valid account/preview access.
- Ensure recovery of unsaved skill output is available after a crash only when the user can actually save it.
- Ensure signed-out users are not prompted to continue unavailable flows.
- Add tests for launch with:
  - signed out + stale review output,
  - preview account + stale review output,
  - free account at limit + stale review output,
  - pro account + stale review output.

Acceptance criteria:

- Recovery behavior is deterministic and documented.

### C8. Hotkey and accessibility failure handling

Problem:

Hotkey errors appear mostly logged. The UI has `hotkeyNote`, but it needs to be wired and tested.

Tasks:

- Surface hotkey registration failure in Flow pane and Settings.
- Provide fallback buttons for all hotkey actions.
- Explain macOS accessibility/input-monitoring requirements if applicable.
- Add tests for hotkey manager failure state.

Acceptance criteria:

- If hotkey registration fails, the app clearly says so and the user can still use buttons.

### C9. Studio section: remove, hide, or document as roadmap

Problem:

Studio appears to be a placeholder. Placeholders are fine for private prototypes, but noisy for V1.

Options:

- Hide Studio until implemented.
- Keep Studio visible but label as "Roadmap" rather than a functional section.
- Build the smallest useful Studio V1.

Recommended V1 path:

- Hide Studio from primary navigation or mark it as roadmap in docs only.

Acceptance criteria:

- No first-run user can mistake Studio for a broken feature.

### C10. Privacy, data, and safety posture

Problem:

The app records screen/audio locally. That needs explicit, careful handling.

Tasks:

- Document exactly what is recorded.
- Document where recordings/logs/skills are stored.
- Document what leaves the machine:
  - runtime prompts to Codex/Claude,
  - MCP data passed to runtime,
  - account/auth calls if any.
- Add in-app link or Settings section to open data locations.
- Add "Delete local data" or at least documented manual deletion paths.
- Ensure logs do not include tokens or raw sensitive screen/audio content unnecessarily.
- Review Keychain storage for token handling.

Acceptance criteria:

- README and Settings make privacy behavior obvious.
- Security policy names local recorder risks.
- No secrets appear in logs during smoke test.

## Track D: Packaging, Signing, and Distribution

### D1. Rewrite installer for Mengo Desktop

Problem:

`install.sh` still installs and launches ScreenpipeMenu/ScreenpipeFlow.

Tasks:

- Update app names and paths:
  - `~/Applications/MengoDesktop.app`
  - GitHub release asset `MengoDesktop.zip`
- Remove ScreenpipeFlow install logic unless intentionally shipping it.
- Make script idempotent.
- Verify old app migration:
  - quit old ScreenpipeMenu if installed,
  - explain old data path if relevant,
  - do not delete old data without confirmation.
- Verify permissions prompt references Mengo Desktop.
- Add a post-install health check.

Acceptance criteria:

- Fresh install from README works.
- Reinstall over previous version works.
- Script output contains no stale app names except migration notes.

### D2. Release artifact naming and versioning

Tasks:

- Add a single source of truth for version number.
- Ensure app bundle version matches GitHub release tag.
- Ensure zip asset name is `MengoDesktop-vX.Y.Z-macos-universal.zip` or similar.
- Generate checksums.
- Create release notes template:
  - highlights,
  - install,
  - upgrade notes,
  - known limitations,
  - checksums,
  - verification commands.

Acceptance criteria:

- A GitHub release can be recreated from documented commands.
- Asset names and release notes match the app.

### D3. Developer ID and notarization

Problem:

Local signing verifies structurally, but Gatekeeper rejects the app because it is self-signed.

Tasks:

- Decide distribution mode:
  - unsigned/dev-only preview,
  - Developer ID signed and notarized public release,
  - Homebrew cask later.
- For public V1, use Apple Developer ID signing and notarization.
- Update `build-mengo.sh` to support:
  - local dev cert,
  - Developer ID Application cert,
  - notarization profile,
  - stapling,
  - verification.
- Add documented environment variables:
  - signing identity,
  - team ID,
  - notarization keychain profile or API key config.
- Verify:
  - `codesign --verify --deep --strict`
  - `spctl --assess --type execute`
  - notarization success
  - staple validation.

Acceptance criteria:

- Downloaded release opens on a clean Mac without right-click bypass.
- Release notes say whether artifact is notarized.

### D4. Architecture and helper packaging

Problem:

MengoDesktop app binary is universal, but embedded screenpipe helper may be host-architecture-specific.

Tasks:

- Determine whether screenpipe helper can be shipped universal.
- If not, publish separate arm64 and x86_64 builds.
- Update build script to either:
  - fetch/build both helper architectures and combine if possible, or
  - produce arch-specific zip assets.
- Add runtime architecture check with clear error if wrong helper is installed.
- Document supported architectures.

Acceptance criteria:

- Release asset works on every architecture claimed in README.
- `file MengoDesktop.app/Contents/MacOS/MengoDesktop` and `file Contents/Helpers/screenpipe` align with release claims.

### D5. Clean app bundle metadata

Tasks:

- Verify bundle identifier is final.
- Verify app display name is final.
- Verify icon is final or acceptable for V1.
- Verify permission strings are accurate and not scary.
- Verify logs path is Mengo-specific.
- Verify menu bar labels are Mengo-specific.
- Verify About window has version and repo link.

Acceptance criteria:

- macOS permission dialogs and About window do not expose legacy branding.

## Track E: Manual Smoke Test Matrix

Use the existing smoke docs as the base, but create one final V1 smoke test at `docs/manual-smoke-tests/mengo-v1.md`.

### E1. Fresh install smoke

- Clean machine or clean user account.
- Install from release zip.
- Launch app.
- Grant Screen Recording.
- Grant Microphone.
- Confirm recorder reaches healthy state.
- Quit and relaunch.
- Confirm recorder state recovers.

### E2. Memory smoke

- Start recording.
- Use several apps/windows.
- Search recent memory.
- Filter by source if source picker is enabled.
- Verify empty/error states.
- Pause and resume.
- Verify no crash if screenpipe is unavailable.

### E3. Flow smoke: primary loop

- Start flow recording from button.
- Start flow recording from hotkey.
- Narrate a simple deterministic workflow.
- Stop.
- Synthesize with chosen default runtime.
- Review generated skill.
- Edit name, description, and parameter.
- Save.
- Verify `SKILL.md`, `flow.json`, and frames exist.
- Invoke the skill from runtime.
- Delete skill from Library.
- Verify files are removed.

### E4. Flow smoke: Codex

- Select Codex runtime.
- Verify executable/preflight.
- Configure MCP if needed.
- Complete record -> synthesize -> review -> save.
- Verify errors say Codex when Codex setup is broken.

### E5. Flow smoke: Claude Code

- Select Claude Code runtime if supported.
- Verify executable/preflight.
- Configure MCP if needed.
- Complete record -> synthesize -> review -> save.
- Verify errors say Claude Code when Claude setup is broken.

### E6. Account/preview smoke

- Launch without preview account.
- Click **Continue in local preview** and confirm the main app opens.
- Launch with `MENGO_PREVIEW_ACCOUNT=free`.
- Launch with `MENGO_PREVIEW_ACCOUNT=pro`.
- Verify free limit behavior.
- Verify pro unlimited behavior.
- Sign out while idle.
- Sign out while recording.
- Sign out while reviewing.

### E7. Failure smoke

- Missing runtime executable.
- Missing MCP configuration.
- Screenpipe stopped.
- Microphone paused/denied.
- Screen recording denied.
- Output directory not writable.
- Duplicate skill name.
- Network unavailable if hosted auth exists.

### E8. Release artifact smoke

- Download zip from GitHub release.
- Verify checksum.
- Unzip.
- Run `codesign --verify --deep --strict`.
- Run `spctl --assess --type execute`.
- Launch via Finder.
- Run the primary loop.

Acceptance criteria:

- Every smoke item is checked for the release candidate.
- Known failures are documented as release blockers or known limitations.

## Track F: Codex for OSS Application Readiness

### F1. Positioning

Core story:

Mengo Desktop is an open-source macOS app for turning local work demonstrations into reusable AI coding/workflow skills. It helps maintainers capture repeatable repository and desktop workflows, synthesize them into skill artifacts, and reuse them with Codex/Claude-style agents. API credits would be used to improve release workflows, automated review, skill synthesis, and maintainer automation around the project itself.

Do not overclaim:

- Do not claim broad adoption unless there are real numbers.
- Do not present upstream screenpipe stars as Mengo Desktop stars.
- It is fair to say Mengo builds on the screenpipe ecosystem if phrased accurately.

### F2. Public metrics to collect before applying

Tasks:

- Capture GitHub repo URL.
- Confirm repo is public.
- Confirm GitHub profile visibility is public.
- Add license.
- Publish V1 or preview release.
- Gather:
  - stars,
  - forks,
  - watchers,
  - release downloads,
  - issues opened/closed,
  - PRs merged,
  - external users/testers if any,
  - demo video link if available.
- Create at least one public demo asset:
  - GIF,
  - short video,
  - screenshots.

Acceptance criteria:

- Application can cite real, current numbers.
- If numbers are small, application emphasizes ecosystem importance and maintainer workflow relevance honestly.

### F3. Application answers draft

The form currently asks for short fields. Keep these under the visible limits.

Repository qualification draft, under 500 characters:

> Mengo Desktop is an open-source macOS app that turns local screen/audio workflow demonstrations into reusable AI skills for Codex/Claude-style agents. It builds on the screenpipe local recording ecosystem and targets maintainer automation: capturing repeated release, triage, review, and repo workflows so they can be replayed reliably. I am the primary maintainer and am preparing its first clean OSS V1 release.

API credit usage draft, under 500 characters:

> I would use API credits for core maintainer workflows: automated PR review, release checklist generation, security-oriented review, docs maintenance, and improving Mengo's skill synthesis/evaluation loop. Credits would also help test Codex-based workflows that convert maintainer actions into reusable skills, directly improving the open-source project.

Anything else draft, under 500 characters:

> Mengo is early, but it is directly aligned with Codex maintainer workflows: it helps capture how maintainers actually work and turn those actions into reusable automation. The V1 plan includes public docs, license/security policy, CI, notarized releases, and Codex runtime smoke tests.

Tasks:

- Rewrite these after V1 cleanup with real metrics.
- Keep claims factual.
- Mention any upstream ecosystem connection only with careful wording.

### F4. Minimum application gate

Do not apply until:

- Repo is public and cleanly branded as Mengo Desktop.
- License exists.
- Security policy exists.
- README has install/build/use docs.
- CI passes.
- A V1 preview release exists with correct asset names.
- At least one runtime works end to end.
- Codex runtime is either working or clearly described as the target use for credits.
- There is a public roadmap/issue list.
- Application copy contains real metrics or honest early-stage positioning.

Stronger application gate:

- Notarized release.
- Demo GIF/video.
- At least a few public issues/PRs.
- One external tester or user testimonial.
- Documented Codex workflow in README.
- Security/privacy docs are explicit.

## Recommended Execution Order

### Sprint 1: Make the repo publicly coherent

Goal:

Make the project stop looking like a rename in progress.

Tasks:

- Fix README.
- Fix install script.
- Fix package/app naming where safe.
- Add license, security, contributing, issue templates.
- Add `.gitignore` cleanup.
- Open public V1 roadmap issues.
- Decide and document account mode for V1.

Release value:

- After this sprint, the repository can be shared without confusing people.

### Sprint 2: Make tests and CI green

Goal:

Create objective maintainability proof.

Tasks:

- Resolve legacy target strategy.
- Fix full `swift test`.
- Fix fixture warning.
- Add GitHub Actions.
- Add test isolation for home-directory reads.
- Remove source tree noise.

Release value:

- After this sprint, the repo has credible active maintenance signals.

### Sprint 3: Fix product trust blockers

Goal:

Make the app's promised behavior match actual behavior.

Tasks:

- Sign-out stops recording.
- Review edits persist.
- Recorder lifecycle duplicate-spawn hardening.
- Recovery prompt gating.
- Hotkey failure UI.
- Source picker process failure handling.

Release value:

- After this sprint, the core app is much safer to hand to testers.

### Sprint 4: Make Codex/runtime story real

Goal:

Align the product with the Codex for OSS narrative.

Tasks:

- Codex runtime smoke test.
- Runtime copy audit.
- Runtime-specific preflight.
- Update manual smoke tests.
- Document exact Codex setup.
- Create demo showing Codex path if it works.

Release value:

- After this sprint, the application story becomes much stronger.

### Sprint 5: Package and release V1 preview

Goal:

Ship a clean public artifact.

Tasks:

- Rewrite release workflow.
- Decide notarization.
- Fix architecture/helper packaging.
- Create checksums.
- Run full smoke matrix.
- Publish V1 preview release.
- Update Codex application answers with real release metrics.

Release value:

- After this sprint, Mengo Desktop is ready for a public Codex for OSS application.

## Release Gate Checklist

V1 release can go out when:

- `swift build` passes.
- `swift test` passes.
- `./build-mengo.sh` passes.
- Code signing verification passes.
- Gatekeeper assessment passes, or release is explicitly labeled non-notarized preview.
- Fresh install smoke passes.
- Memory smoke passes.
- Flow primary loop smoke passes.
- Runtime smoke passes for every runtime claimed in README.
- Sign-out while recording stops recording.
- Review edits persist to disk.
- README/install/release assets have no stale ScreenpipeMenu branding.
- License/security/contributing docs exist.
- CI passes on GitHub.
- Release notes include known limitations.

## Codex for OSS Application Gate Checklist

Apply when:

- The repo looks maintained in public.
- The app has a clean release or preview release.
- The README explains Codex relevance clearly.
- Public docs show maintainer workflows, not just end-user app features.
- Application answers include real metrics or honest early-stage ecosystem rationale.
- You can truthfully say how API credits will be used for OSS maintainer work.
- The GitHub repository URL, GitHub profile, and role fields are ready.

## Highest-Risk Items

1. Account backend ambiguity can make the app unusable for new users.
2. Gatekeeper rejection will reduce trust unless the release is clearly preview-only.
3. Review UI currently appears to promise edits that may not persist.
4. Sign-out recording behavior is a privacy/trust risk.
5. Legacy Screenpipe branding weakens the public application immediately.
6. Full test suite failure weakens maintainability evidence.
7. Codex support must be real or carefully framed.

## First Ten Concrete Issues to Open

1. `docs: rewrite README for Mengo Desktop V1`
2. `release: replace ScreenpipeMenu installer with MengoDesktop installer`
3. `oss: add LICENSE, SECURITY.md, CONTRIBUTING.md, and issue templates`
4. `build: make swift test pass from a clean checkout`
5. `ci: add macOS build and test workflow`
6. `privacy: stop recorder immediately on sign-out`
7. `flow: persist review edits to SKILL.md and flow metadata`
8. `runtime: verify and document Codex synthesis path`
9. `release: add Developer ID notarization path`
10. `docs: create V1 manual smoke test checklist`

## Recommended Immediate Next Move

Start with Sprint 1. It has the highest leverage for both V1 and the Codex application because the current public presentation is the largest mismatch with the product's actual potential. Then do Sprint 2 before deeper product changes so every future fix lands on a green test/CI base.
