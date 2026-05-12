# Mengo Desktop — Phase 1 "The Shell" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a launchable Mengo Desktop macOS app — a Dock-icon SwiftUI app with a left-sidebar main window (placeholder panes for Memory / Flow / Library / Studio / Settings), a single menu bar dropdown, lifecycle plumbing, a design-token file, the app icon, and a `.app` build script — with no recording, synthesis, or licensing.

**Architecture:** New `MengoDesktop` executable target under `Sources/MengoDesktop/`, alongside the untouched V1 `ScreenpipeMenu` / `ScreenpipeFlow` targets. SwiftUI `App` with one singleton `Window` scene (`NavigationSplitView`) and one `MenuBarExtra` (`.menu` style); a thin `@Observable` `AppState` holds the sidebar selection; an `NSApplicationDelegate` carries `applicationWillTerminate`. Packaged as a universal, ad-hoc-signed `.app` by `build-mengo.sh`, mirroring `build-flow.sh`.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, SwiftPM, XCTest, macOS 15+, `sips` + `iconutil` + `codesign` + `ditto` for packaging.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-phase-1-shell-design.md`](../specs/2026-05-12-mengo-phase-1-shell-design.md)

---

## File Structure

Created under `Sources/MengoDesktop/`:

| File | Responsibility |
|---|---|
| `SidebarSection.swift` | `enum SidebarSection` — the five product sections + their presentation data (`displayName`, `badge`, `systemImage`, `phase`, `comingSoonBlurb`). Pure data, no AppKit/SwiftUI. |
| `AppState.swift` | `@MainActor @Observable final class AppState` — holds `selectedSection: SidebarSection`. The seam later phases extend. |
| `Theme.swift` | `enum Theme` — design tokens: brand accent (the icon orange) + semantic colors (mapped to system `NSColor`s) + a small `Font` type scale. Starter values. |
| `Log.swift` | `enum Log` — minimal file logger to `~/Library/Logs/MengoDesktop/app.log`; `bootstrap()` (stdout/stderr redirect + launch line) and `line(_:)`. Adapted from V1's `ScreenpipeFlow/Logger.swift`. |
| `ComingSoonPane.swift` | `struct ComingSoonPane: View` — one parametrized placeholder pane (big SF Symbol + section name + "Coming in Phase N" + blurb), reused for all five sidebar rows. |
| `MainWindowView.swift` | `struct MainWindowView: View` — the `NavigationSplitView`: sidebar `List` of `SidebarSection`s + `ComingSoonPane` detail. Bridges `List`'s optional selection binding to `AppState.selectedSection`. |
| `MenuBarContent.swift` | `struct MenuBarContent: View` — the menu bar dropdown: disabled Memory/Flow groups, Library/Studio/Settings nav entries, Quit. |
| `MengoDesktopApp.swift` | `@main @MainActor struct MengoDesktopApp: App` — the `Window` + `MenuBarExtra` scenes; owns `@State AppState`; `init()` calls `Log.bootstrap()`. Also declares `final class AppDelegate: NSObject, NSApplicationDelegate` (in-file) with `applicationWillTerminate` → `Log.line("app terminating")`. |

Created under `Tests/MengoDesktopTests/`:

| File | Responsibility |
|---|---|
| `SidebarSectionTests.swift` | Cases/order, presentation-string non-emptiness, phase range, the Studio "Pro" badge, `id` ↔ `rawValue`. |
| `AppStateTests.swift` | Fresh `AppState` opens on `.memory`; `selectedSection` is mutable. |

Other files:

| File | Action |
|---|---|
| `Package.swift` | **Modify** — add the `MengoDesktop` executable target (Task 1) and the `MengoDesktopTests` test target (Task 2). The `ScreenpipeMenu` / `ScreenpipeFlow` target definitions are not touched. |
| `Resources/MengoDesktopInfo.plist` | **Create** — minimal `Info.plist` (id `ai.mengo.desktop`, `LSUIElement` false, `CFBundleIconFile AppIcon`, …). |
| `Resources/AppIcon.png` | **Create** — the user-provided artwork, moved from the worktree-root `mengo-app-icon.png`. The committed single source for the icon. |
| `build-mengo.sh` | **Create** — universal build + `.app` assembly + `.icns` generation + ad-hoc/dev-cert signing + zip. Mirrors `build-flow.sh`. |
| `.gitignore` | **Modify** — add `MengoDesktop.app/` and `MengoDesktop.zip`. |
| `docs/manual-smoke-tests/mengo-phase-1-shell.md` | **Create** — the pre-tag checklist. |

**Working directory for every command below:** the repo root of the `mengo/phase-1-shell` worktree (the directory containing `Package.swift`).

---

## Task 1: Scaffold the `MengoDesktop` executable target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MengoDesktop/MengoDesktopApp.swift`

- [ ] **Step 1: Add the executable target to `Package.swift`**

Open `Package.swift`. It currently ends its `targets:` array with the `ScreenpipeFlow` executable target and the `ScreenpipeFlowTests` test target. Add a new executable target after `ScreenpipeFlowTests` (before the closing `]` of `targets:`). The file should become:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenpipeMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenpipeMenu",
            path: "Sources/ScreenpipeMenu"
        ),
        .testTarget(
            name: "ScreenpipeMenuTests",
            dependencies: ["ScreenpipeMenu"],
            path: "Tests/ScreenpipeMenuTests"
        ),
        .executableTarget(
            name: "ScreenpipeFlow",
            path: "Sources/ScreenpipeFlow",
            resources: [
                .copy("../../Resources/synthesis-prompt.md")
            ]
        ),
        .testTarget(
            name: "ScreenpipeFlowTests",
            dependencies: ["ScreenpipeFlow"],
            path: "Tests/ScreenpipeFlowTests"
        ),
        .executableTarget(
            name: "MengoDesktop",
            path: "Sources/MengoDesktop"
        )
    ]
)
```

- [ ] **Step 2: Create a minimal `@main` app so the target compiles**

Create `Sources/MengoDesktop/MengoDesktopApp.swift`:

```swift
import SwiftUI

@main
@MainActor
struct MengoDesktopApp: App {
    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            Text("Mengo Desktop")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
```

- [ ] **Step 3: Build the new target**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!` (no errors).

- [ ] **Step 4: Confirm the existing targets still build**

Run: `swift build`
Expected: `Build complete!` — `ScreenpipeMenu`, `ScreenpipeFlow`, and `MengoDesktop` all compile.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/MengoDesktop/MengoDesktopApp.swift
git commit -m "MengoDesktop: scaffold executable target + minimal @main app"
```

---

## Task 2: `SidebarSection` enum + test target

**Files:**
- Modify: `Package.swift`
- Create: `Tests/MengoDesktopTests/SidebarSectionTests.swift`
- Create: `Sources/MengoDesktop/SidebarSection.swift`

- [ ] **Step 1: Add the test target to `Package.swift`**

Append a `MengoDesktopTests` test target after the `MengoDesktop` executable target inside `targets:`:

```swift
        .executableTarget(
            name: "MengoDesktop",
            path: "Sources/MengoDesktop"
        ),
        .testTarget(
            name: "MengoDesktopTests",
            dependencies: ["MengoDesktop"],
            path: "Tests/MengoDesktopTests"
        )
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MengoDesktopTests/SidebarSectionTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class SidebarSectionTests: XCTestCase {

    func test_allCases_areTheFiveSectionsInOrder() {
        XCTAssertEqual(
            SidebarSection.allCases,
            [.memory, .flow, .library, .studio, .settings]
        )
    }

    func test_everyCase_hasNonEmptyPresentationStrings() {
        for section in SidebarSection.allCases {
            XCTAssertFalse(section.displayName.isEmpty, "\(section): displayName")
            XCTAssertFalse(section.systemImage.isEmpty, "\(section): systemImage")
            XCTAssertFalse(section.comingSoonBlurb.isEmpty, "\(section): comingSoonBlurb")
        }
    }

    func test_everyCase_targetsAPhaseBetween2And5() {
        for section in SidebarSection.allCases {
            XCTAssertTrue((2...5).contains(section.phase),
                          "\(section): phase \(section.phase) out of range")
        }
    }

    func test_onlyStudioCarriesAProBadge() {
        for section in SidebarSection.allCases {
            if section == .studio {
                XCTAssertEqual(section.badge, "Pro")
            } else {
                XCTAssertNil(section.badge, "\(section) should have no badge")
            }
        }
    }

    func test_id_equalsRawValue() {
        for section in SidebarSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
        }
    }
}
```

- [ ] **Step 3: Run the test — expect a compile failure**

Run: `swift test --filter SidebarSectionTests`
Expected: FAIL — compile error, "cannot find type 'SidebarSection' in scope" (the enum doesn't exist yet).

- [ ] **Step 4: Create the enum**

Create `Sources/MengoDesktop/SidebarSection.swift`:

```swift
import Foundation

/// The five product/area sections in Mengo Desktop's main-window sidebar.
/// In Phase 1 each one shows a placeholder pane; later phases fill them in.
enum SidebarSection: String, CaseIterable, Identifiable {
    case memory
    case flow
    case library
    case studio
    case settings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .memory:   return "Memory"
        case .flow:     return "Flow"
        case .library:  return "Library"
        case .studio:   return "Studio"
        case .settings: return "Settings"
        }
    }

    /// A short suffix shown after the name (sidebar row and menu item).
    /// `nil` for everything except Studio's "Pro" tag.
    var badge: String? {
        switch self {
        case .studio: return "Pro"
        default:      return nil
        }
    }

    /// SF Symbol name for the section's icon. (Indicative — fine to refine.)
    var systemImage: String {
        switch self {
        case .memory:   return "brain"
        case .flow:     return "wand.and.stars"
        case .library:  return "books.vertical"
        case .studio:   return "point.3.connected.trianglepath.dotted"
        case .settings: return "gearshape"
        }
    }

    /// The Mengo Desktop phase that replaces this section's placeholder with
    /// real content.
    var phase: Int {
        switch self {
        case .memory:   return 2
        case .flow:     return 3
        case .library:  return 3
        case .studio:   return 5
        case .settings: return 4
        }
    }

    /// One-line description shown on the placeholder pane.
    var comingSoonBlurb: String {
        switch self {
        case .memory:
            return "Always-on local recording of your screen, mic, and accessibility tree."
        case .flow:
            return "Record a task once and get a reusable Claude Code skill out of it."
        case .library:
            return "Your saved flows — re-open, rename, delete."
        case .studio:
            return "A visual editor for your flows, plus replay."
        case .settings:
            return "Capture, storage, hotkeys, account, privacy."
        }
    }
}
```

- [ ] **Step 5: Run the test — expect PASS**

Run: `swift test --filter SidebarSectionTests`
Expected: PASS — 5 tests, 0 failures.

- [ ] **Step 6: Confirm the app target still builds**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Package.swift Tests/MengoDesktopTests/SidebarSectionTests.swift Sources/MengoDesktop/SidebarSection.swift
git commit -m "MengoDesktop: SidebarSection enum + test target (TDD)"
```

---

## Task 3: `AppState` (sidebar selection holder)

**Files:**
- Create: `Tests/MengoDesktopTests/AppStateTests.swift`
- Create: `Sources/MengoDesktop/AppState.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MengoDesktopTests/AppStateTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

@MainActor
final class AppStateTests: XCTestCase {

    func test_freshState_opensOnMemory() {
        XCTAssertEqual(AppState().selectedSection, .memory)
    }

    func test_selectedSection_isMutable() {
        let state = AppState()
        state.selectedSection = .studio
        XCTAssertEqual(state.selectedSection, .studio)
    }
}
```

- [ ] **Step 2: Run the test — expect a compile failure**

Run: `swift test --filter AppStateTests`
Expected: FAIL — compile error, "cannot find 'AppState' in scope".

- [ ] **Step 3: Create `AppState`**

Create `Sources/MengoDesktop/AppState.swift`:

```swift
import Foundation
import Observation

/// App-wide state. In Phase 1 it holds just the sidebar selection — the
/// binding the main window's `List` and the menu bar's navigation entries
/// both drive. Later phases extend it (recorder status, Flow session,
/// account/license state).
@Observable
@MainActor
final class AppState {
    /// The section currently shown in the main window. Defaults to Memory,
    /// so the app opens on the Memory pane.
    var selectedSection: SidebarSection = .memory
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `swift test --filter AppStateTests`
Expected: PASS — 2 tests, 0 failures.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: PASS — all `MengoDesktopTests` (and the existing `ScreenpipeMenuTests` / `ScreenpipeFlowTests`) pass.

- [ ] **Step 6: Commit**

```bash
git add Tests/MengoDesktopTests/AppStateTests.swift Sources/MengoDesktop/AppState.swift
git commit -m "MengoDesktop: AppState holds sidebar selection (TDD)"
```

---

## Task 4: `Theme` design tokens

**Files:**
- Create: `Sources/MengoDesktop/Theme.swift`

(No unit test — these are constants. Verified by compilation and by the placeholder pane using them.)

- [ ] **Step 1: Create `Theme.swift`**

Create `Sources/MengoDesktop/Theme.swift`:

```swift
import SwiftUI
import AppKit

/// Mengo Desktop's design tokens, defined once. The colour/weight values
/// below are starter values — sampled from the app icon and the system
/// palette. If a fuller mengo.ai brand kit (typeface, extended palette)
/// becomes available, change it here.
enum Theme {

    // MARK: - Colours

    /// Brand accent — the warm orange of the app icon
    /// (≈ #FB8420; the icon's field runs ≈#FD9A1E → ≈#F96B1B top-to-bottom).
    static let accent = Color(red: 251.0 / 255.0, green: 132.0 / 255.0, blue: 32.0 / 255.0)

    /// Background behind the whole window / sidebar.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    /// Background behind a content pane.
    static let paneBackground = Color(nsColor: .textBackgroundColor)
    /// Hairline separators.
    static let separator = Color(nsColor: .separatorColor)
    /// Primary text.
    static let primaryText = Color(nsColor: .labelColor)
    /// De-emphasised / secondary text.
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    // MARK: - Typography

    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.semibold)
    static let title      = Font.system(.title, design: .default).weight(.semibold)
    static let headline   = Font.system(.headline, design: .default)
    static let body       = Font.system(.body, design: .default)
    static let caption    = Font.system(.caption, design: .default)
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/Theme.swift
git commit -m "MengoDesktop: Theme design tokens (accent + semantic colours + type scale)"
```

---

## Task 5: `Log` file logger

**Files:**
- Create: `Sources/MengoDesktop/Log.swift`

(No unit test — `bootstrap()` does process-global stdout/stderr redirection, which is awkward to test in-process and matches V1's untested logger. Exercised by the manual smoke checklist: `app.log` must contain a launch line and a terminate line.)

- [ ] **Step 1: Create `Log.swift`**

Create `Sources/MengoDesktop/Log.swift`:

```swift
import Foundation

/// Minimal file logger. A Finder-launched `.app` has no attached terminal,
/// so `bootstrap()` redirects stdout/stderr into a log file; `line(_:)`
/// appends a timestamped line. Adapted from V1's `ScreenpipeFlow/Logger`.
enum Log {

    /// `~/Library/Logs/MengoDesktop/` — created on first access.
    static let directory: URL = {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/MengoDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// `~/Library/Logs/MengoDesktop/app.log`.
    static let fileURL: URL = directory.appendingPathComponent("app.log")

    /// Call once at process start (from `MengoDesktopApp.init()`). Redirects
    /// stdout + stderr to `app.log` (unbuffered) and writes a launch line.
    static func bootstrap() {
        freopen(fileURL.path, "a+", stdout)
        freopen(fileURL.path, "a+", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        line("app launched, pid=\(getpid())")
    }

    /// Append a timestamped line to `app.log` (via the redirected stdout).
    static func line(_ message: String) {
        print("[\(Date())] \(message)")
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/Log.swift
git commit -m "MengoDesktop: Log — minimal file logger to ~/Library/Logs/MengoDesktop/app.log"
```

---

## Task 6: `ComingSoonPane` placeholder view

**Files:**
- Create: `Sources/MengoDesktop/ComingSoonPane.swift`

(No unit test — SwiftUI view; this repo has no view-snapshot infra. Verified visually in the smoke checklist.)

- [ ] **Step 1: Create `ComingSoonPane.swift`**

Create `Sources/MengoDesktop/ComingSoonPane.swift`:

```swift
import SwiftUI

/// The placeholder shown in the main window's detail column for every
/// sidebar section in Phase 1: a large glyph, the section name, which phase
/// fills it in, and a one-line blurb. Later phases swap real panes in.
struct ComingSoonPane: View {
    let section: SidebarSection

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            Text(section.displayName)
                .font(Theme.title)
                .foregroundStyle(Theme.primaryText)

            Text("Coming in Phase \(section.phase)")
                .font(Theme.headline)
                .foregroundStyle(Theme.secondaryText)

            Text(section.comingSoonBlurb)
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paneBackground)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/ComingSoonPane.swift
git commit -m "MengoDesktop: ComingSoonPane — parametrized placeholder pane"
```

---

## Task 7: `MainWindowView` (sidebar + detail)

**Files:**
- Create: `Sources/MengoDesktop/MainWindowView.swift`

(No unit test — SwiftUI view. Verified visually in the smoke checklist.)

- [ ] **Step 1: Create `MainWindowView.swift`**

Create `Sources/MengoDesktop/MainWindowView.swift`:

```swift
import SwiftUI

/// The main window: a `NavigationSplitView` with a five-row sidebar and a
/// `ComingSoonPane` in the detail column. The sidebar selection lives in
/// `AppState` so the menu bar can drive it too.
struct MainWindowView: View {
    let appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(SidebarSection.allCases) { section in
                    Label {
                        HStack(spacing: 6) {
                            Text(section.displayName)
                            if let badge = section.badge {
                                Spacer(minLength: 0)
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    } icon: {
                        Image(systemName: section.systemImage)
                    }
                    .tag(section)
                }
            }
            .navigationTitle("Mengo")
            .frame(minWidth: 190)
        } detail: {
            ComingSoonPane(section: appState.selectedSection)
        }
    }

    /// `List` single-selection wants a `Binding<SidebarSection?>`; `AppState`
    /// keeps a non-optional `selectedSection`. Bridge here, ignoring any
    /// transient deselect-to-`nil`.
    private var selectionBinding: Binding<SidebarSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { if let newValue = $0 { appState.selectedSection = newValue } }
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MainWindowView.swift
git commit -m "MengoDesktop: MainWindowView — NavigationSplitView sidebar + detail"
```

---

## Task 8: `MenuBarContent` (menu bar dropdown)

**Files:**
- Create: `Sources/MengoDesktop/MenuBarContent.swift`

(No unit test — SwiftUI view. Verified visually in the smoke checklist.)

- [ ] **Step 1: Create `MenuBarContent.swift`**

Create `Sources/MengoDesktop/MenuBarContent.swift`:

```swift
import SwiftUI
import AppKit

/// The dropdown shown from the menu bar item. In Phase 1 the Memory and Flow
/// groups are present but disabled (those products don't exist yet);
/// Library / Studio / Settings raise the main window on that section; Quit
/// terminates.
struct MenuBarContent: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Mengo")
            .font(.headline)

        Divider()

        // MARK: Memory (Phase 2)
        Text("Memory")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("Pause audio") { }.disabled(true)
        Button("Pause screen") { }.disabled(true)
        Button("Open data folder") { }.disabled(true)

        // MARK: Flow (Phase 3)
        Text("Flow")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("Start recording…") { }.disabled(true)
        Button("Grab last 5 minutes…") { }.disabled(true)

        Divider()

        Button("Library") { reveal(.library) }
        Button(menuTitle(for: .studio)) { reveal(.studio) }
        Button("Settings…") { reveal(.settings) }

        Divider()

        Button("Quit Mengo Desktop") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// "Studio" + the section's badge in parens, e.g. "Studio (Pro)".
    private func menuTitle(for section: SidebarSection) -> String {
        if let badge = section.badge { return "\(section.displayName) (\(badge))" }
        return section.displayName
    }

    /// Select `section` in `AppState` and bring the main window to the front.
    private func reveal(_ section: SidebarSection) {
        appState.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MenuBarContent.swift
git commit -m "MengoDesktop: MenuBarContent — menu bar dropdown (disabled Memory/Flow, nav, Quit)"
```

---

## Task 9: Wire it all together in `MengoDesktopApp` + `AppDelegate`

**Files:**
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift` (replace the minimal Task-1 version)

(No unit test — app entry point. Exercised end-to-end by the smoke checklist.)

- [ ] **Step 1: Replace `MengoDesktopApp.swift` with the full version**

Overwrite `Sources/MengoDesktop/MengoDesktopApp.swift`:

```swift
import SwiftUI
import AppKit

@main
@MainActor
struct MengoDesktopApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            MainWindowView(appState: appState)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 840, height: 560)

        MenuBarExtra {
            MenuBarContent(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Text("Mengo")
                Image(systemName: "circle.dotted")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Carries the lifecycle callbacks SwiftUI's scene phase doesn't reliably
/// surface — in particular `applicationWillTerminate` (logout/shutdown/⌘Q).
/// In Phase 1 it just logs; Phase 2 hooks recorder shutdown in here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Log.line("app terminating")
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

> If Swift 6 strict concurrency complains about constructing `AppState()` (a `@MainActor` type) in the `@State` default: the `MengoDesktopApp` struct is already marked `@MainActor`, so `init()` and the property initializers run in main-actor context — this should compile. If it still complains in some toolchain, move the construction into `init()` via `_appState = State(initialValue: AppState())` (the V1 `ScreenpipeFlowApp` pattern).

- [ ] **Step 3: Run the full test suite (nothing should have broken)**

Run: `swift test`
Expected: PASS — all targets' tests green.

- [ ] **Step 4: Commit**

```bash
git add Sources/MengoDesktop/MengoDesktopApp.swift
git commit -m "MengoDesktop: wire App scenes (Window + MenuBarExtra) + AppDelegate lifecycle"
```

---

## Task 10: `Info.plist` + `.gitignore`

**Files:**
- Create: `Resources/MengoDesktopInfo.plist`
- Modify: `.gitignore`

- [ ] **Step 1: Create `Resources/MengoDesktopInfo.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MengoDesktop</string>
    <key>CFBundleIdentifier</key>
    <string>ai.mengo.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mengo Desktop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Add the build artifacts to `.gitignore`**

Edit `.gitignore`. After the `ScreenpipeFlow.app/` / `ScreenpipeFlow.zip` lines, add:

```
MengoDesktop.app/
MengoDesktop.zip
```

The file should become:

```
.build/
.build-cache/
.swiftpm/
DerivedData/
*.xcodeproj
ScreenpipeMenu.app/
ScreenpipeMenu.zip
ScreenpipeFlow.app/
ScreenpipeFlow.zip
MengoDesktop.app/
MengoDesktop.zip
*.dSYM
.DS_Store
```

- [ ] **Step 3: Commit**

```bash
git add Resources/MengoDesktopInfo.plist .gitignore
git commit -m "MengoDesktop: Info.plist (LSUIElement=false, ai.mengo.desktop) + .gitignore artifacts"
```

---

## Task 11: App icon → `Resources/AppIcon.png`, and `build-mengo.sh`

**Files:**
- Move: `mengo-app-icon.png` → `Resources/AppIcon.png`
- Create: `build-mengo.sh`

- [ ] **Step 1: Move the provided artwork into `Resources/`**

The user dropped `mengo-app-icon.png` at the worktree root (untracked). Move it to the conventional location:

```bash
mv mengo-app-icon.png Resources/AppIcon.png
```

- [ ] **Step 2: Create `build-mengo.sh`**

Create `build-mengo.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MengoDesktop"
BUNDLE_ID="ai.mengo.desktop"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.png"

cd "$PROJECT_DIR"

echo "==> Building $APP_NAME (universal)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/MengoDesktopInfo.plist "$APP_BUNDLE/Contents/Info.plist"

# Generate AppIcon.icns from the committed source PNG (single source of truth).
if [ -f "$ICON_SRC" ]; then
    echo "==> Generating AppIcon.icns from Resources/AppIcon.png"
    TMPDIR_ICON="$(mktemp -d)"
    ICONSET="$TMPDIR_ICON/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$TMPDIR_ICON"
else
    echo "WARNING: $ICON_SRC not found — building without a custom app icon"
fi

# Signing: prefer the self-signed dev cert (stable identity across rebuilds —
# matters once later phases rely on TCC grants surviving), else ad-hoc.
CERT_NAME="ScreenpipeMenu Local Dev"
CERT_LINE=$(security find-identity -p basic login.keychain 2>/dev/null | grep "$CERT_NAME" || true)
CERT_SHA=$(echo "$CERT_LINE" | awk '{print $2}' | head -1)

if [ -n "$CERT_SHA" ]; then
    SIGN_IDENTITY="$CERT_SHA"
    echo "==> Codesigning with '$CERT_NAME' ($CERT_SHA)"
else
    SIGN_IDENTITY="-"
    echo "==> Codesigning ad-hoc (run ./bootstrap-cert.sh once for stable signing)"
fi

codesign --sign "$SIGN_IDENTITY" --force --identifier "$BUNDLE_ID" "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x build-mengo.sh
```

- [ ] **Step 4: Run it**

Run: `./build-mengo.sh`
Expected: ends with `Done.` and prints paths to `MengoDesktop.app` and `MengoDesktop.zip`. No errors.

- [ ] **Step 5: Verify the bundle**

```bash
test -f MengoDesktop.app/Contents/MacOS/MengoDesktop && echo "binary OK"
test -f MengoDesktop.app/Contents/Resources/AppIcon.icns && echo "icon OK"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' MengoDesktop.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' MengoDesktop.app/Contents/Info.plist
codesign -dv MengoDesktop.app 2>&1 | grep -E 'Identifier|Signature'
```
Expected: `binary OK`, `icon OK`, `ai.mengo.desktop`, `false`, and a codesign identifier of `ai.mengo.desktop`.

- [ ] **Step 6: Commit (the `.app` / `.zip` are gitignored — only the script + the icon source)**

```bash
git add build-mengo.sh Resources/AppIcon.png
git commit -m "MengoDesktop: build-mengo.sh (.app assembly, .icns generation, signing) + app icon source"
```

---

## Task 12: Manual smoke-test checklist + run it

**Files:**
- Create: `docs/manual-smoke-tests/mengo-phase-1-shell.md`

- [ ] **Step 1: Create the checklist doc**

Create `docs/manual-smoke-tests/mengo-phase-1-shell.md`:

```markdown
# Manual Smoke Test — Mengo Desktop Phase 1 ("The Shell")

Run this before tagging `mengo-v2-phase-1-shell`. Spec:
`docs/superpowers/specs/2026-05-12-mengo-phase-1-shell-design.md`.

## Build & tests (scriptable)

- [ ] `swift build` — all targets compile (`ScreenpipeMenu`, `ScreenpipeFlow`, `MengoDesktop`).
- [ ] `swift test` — all tests pass.
- [ ] `./build-mengo.sh` — completes, produces `MengoDesktop.app` and `MengoDesktop.zip`.
- [ ] `MengoDesktop.app/Contents/Resources/AppIcon.icns` exists; `Info.plist` has `CFBundleIdentifier = ai.mengo.desktop` and `LSUIElement = false`.

## App behaviour (run `open MengoDesktop.app`)

- [ ] A **Dock icon** (the mango) appears, and the app shows up in ⌘-Tab.
- [ ] The main window opens with a sidebar of exactly five rows — Memory, Flow, Library, Studio (with a "Pro" badge), Settings — and the **Memory** pane selected.
- [ ] Each pane shows: a large glyph, the section name, "Coming in Phase N" (Memory→2, Flow→3, Library→3, Settings→4, Studio→5), and a one-line blurb.
- [ ] Clicking each sidebar row swaps the detail pane to that section.
- [ ] A **menu bar item** labelled "Mengo" appears. Opening it shows: a "Mengo" header; a "Memory" group (Pause audio / Pause screen / Open data folder — all greyed out); a "Flow" group (Start recording… / Grab last 5 minutes… — greyed out); then Library, Studio (Pro), Settings…; then Quit Mengo Desktop (⌘Q).
- [ ] Clicking **Library** / **Studio (Pro)** / **Settings…** in the menu brings the main window to the front with that section selected.
- [ ] **Quit** (menu item or ⌘Q) terminates the app cleanly.
- [ ] `~/Library/Logs/MengoDesktop/app.log` exists and contains an `app launched, pid=…` line and an `app terminating` line.
```

- [ ] **Step 2: Run the scriptable portion**

```bash
swift build
swift test
./build-mengo.sh
test -f MengoDesktop.app/Contents/Resources/AppIcon.icns && echo "icon OK"
```
Expected: build complete, all tests pass, build script done, `icon OK`.

- [ ] **Step 3: Run the app-behaviour portion**

Run `open MengoDesktop.app` and walk the "App behaviour" checkboxes above. (This needs a human at the machine, or — if executing this plan via an agent with desktop control — the computer-use tools. Fix anything that fails and re-run the relevant earlier task.)

- [ ] **Step 4: Commit the checklist**

```bash
git add docs/manual-smoke-tests/mengo-phase-1-shell.md
git commit -m "MengoDesktop: Phase 1 manual smoke-test checklist"
```

- [ ] **Step 5: (Optional) tag the phase release once the checklist passes**

```bash
git tag mengo-v2-phase-1-shell
```

---

## Done criteria

- `swift build` and `swift test` pass; `./build-mengo.sh` produces a launchable, ad-hoc-signed `MengoDesktop.app` with the mango icon.
- Launching it gives a Dock icon, a five-row-sidebar window with placeholder panes, and a "Mengo" menu bar dropdown whose Memory/Flow items are disabled and whose Library/Studio/Settings items navigate the window.
- `Sources/ScreenpipeMenu/` and `Sources/ScreenpipeFlow/` are untouched; the only modified pre-existing files are `Package.swift` and `.gitignore`.
- The manual smoke checklist (`docs/manual-smoke-tests/mengo-phase-1-shell.md`) passes.
