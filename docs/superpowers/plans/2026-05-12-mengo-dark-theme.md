# Mengo Desktop — Dark Brand Theme + Logo + Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Mengo Desktop look finished — adopt the mengo.ai dark brand palette as a fixed theme, force the app dark, bring the mango logo into the sidebar header, restyle the Memory pane / placeholder panes / menu in the palette with SF Symbol icons on every action, and add tasteful animations (pulsing+glowing recording dot, rolling stat numbers, section-switch crossfade, hover lifts, banner springs, fade-in).

**Architecture:** `Theme.swift` becomes a fixed dark palette (hex literals) plus functional recorder-state colours (green / brand-orange / red). `Brand.swift` loads the bundled logo PNG. The app sets `NSApp.appearance = .darkAqua` at launch. The views restyle against `Theme`; animations are SwiftUI modifiers (`.symbolEffect`, `.contentTransition(.numericText())`, transitions, `.onHover`). No new types beyond `Brand`; no `Package.swift` change — the logo is copied into the `.app` by `build-mengo.sh` like `AppIcon.icns`.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, SwiftPM, XCTest.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-dark-theme-design.md`](../specs/2026-05-12-mengo-dark-theme-design.md)

**Working directory for every command:** `/Users/your-user/screenpipe/.claude/worktrees/mengo-phase-1-shell` (holds the `mengo/memory-pane-redesign` branch; this work continues on it).

---

## File Structure

| File | Change |
|---|---|
| `Sources/MengoDesktop/Theme.swift` | **Rewrite** — the mengo.ai dark palette as hex literals (`windowBackground` `#121315`, `paneBackground` `#17181B`, `cardBackground` `#1D1F23`, `elevatedBackground` `#22242A`, `separator` `#2A2D33`, `primaryText` `#F3F4F6`, `secondaryText` `#A6ADB8`, `mutedText` `#737A86`, `accent` `#FF8A3D`, `accentHover` `#FF9D5C`, `accentGlow` `#FF8A3D`@18%); recorder-state colours `recording` `#3DD56B` (green), `paused` = `accent` (orange), `stopped` `#E5484D` (red); keep the typography tokens; add a fileprivate `Color(hex:)`. |
| `Sources/MengoDesktop/Brand.swift` | **New** — `enum Brand { static let logo: Image? }` (nil-safe `Bundle.main` load of `MengoLogo.png`). |
| `Resources/MengoLogo.png` | **New** — copied from `~/Desktop/Mengo.ai/public/logo.png` (transparent mango). |
| `build-mengo.sh` | **Modify** — copy `Resources/MengoLogo.png` → `Contents/Resources/MengoLogo.png` in the assembly step. |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | **Modify** — `AppDelegate.applicationDidFinishLaunching` sets `NSApp.appearance = NSAppearance(named: .darkAqua)`. |
| `Sources/MengoDesktop/MainWindowView.swift` | **Rewrite** — sidebar = `VStack { logo-wordmark header; List }` on `windowBackground`; `.tint(Theme.accent)` for the selection highlight; remove `.navigationTitle`; detail content keyed/`.id`-swapped with a crossfade. |
| `Sources/MengoDesktop/MemoryPane.swift` | **Rewrite** — dark-palette restyle; subtle pane gradient; SF Symbol icons on all action buttons; recording-dot glow halo; `.contentTransition(.numericText())` on the stat numbers; hero status crossfade; degraded-banner spring; stat-tile hover lift; fade-in on appear. |
| `Sources/MengoDesktop/ComingSoonPane.swift` | **Modify** — restyle for the dark palette (mostly automatic via the new `Theme` values; add a soft `accentGlow` halo behind the big glyph for consistency with the Memory hero). |
| `Sources/MengoDesktop/MenuBarContent.swift` | **Modify** — add SF Symbol icons to the Memory-group menu items (`Button { } label: { Label(_, systemImage:) }`). (`MenuBarLabel`'s colours already come from `Theme` — they just change value.) |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | **Modify** — update "App behaviour" for the dark theme / logo / icons / animations. |

No new Swift unit tests (colours, the logo bundle, animations aren't unit-testable here). `swift build` + `swift test` (the existing 73) plus the manual smoke checklist are the gate.

---

## Task 1: `Theme.swift` — the dark brand palette

**Files:**
- Rewrite: `Sources/MengoDesktop/Theme.swift`

- [ ] **Step 1: Replace `Theme.swift`**

Overwrite `Sources/MengoDesktop/Theme.swift`:

```swift
import SwiftUI
import AppKit

/// Mengo Desktop's design tokens — the mengo.ai brand dark palette (the app
/// forces `.darkAqua`, see `MengoDesktopApp`). Recorder-state colours are
/// functional, not part of the brand palette: green / brand-orange / red.
enum Theme {

    // MARK: - Brand palette (mengo.ai dark)

    static let windowBackground   = Color(hex: 0x121315)
    static let paneBackground     = Color(hex: 0x17181B)
    static let cardBackground     = Color(hex: 0x1D1F23)
    static let elevatedBackground = Color(hex: 0x22242A)   // hover surface, one notch up
    static let separator          = Color(hex: 0x2A2D33)

    static let primaryText   = Color(hex: 0xF3F4F6)
    static let secondaryText = Color(hex: 0xA6ADB8)
    static let mutedText     = Color(hex: 0x737A86)

    static let accent      = Color(hex: 0xFF8A3D)
    static let accentHover = Color(hex: 0xFF9D5C)
    static let accentGlow  = Color(hex: 0xFF8A3D).opacity(0.18)

    // MARK: - Recorder state colours (functional)

    static let recording = Color(hex: 0x3DD56B)   // green — recording
    static let paused    = accent                  // orange — paused (audio/screen/both)
    static let stopped   = Color(hex: 0xE5484D)   // red — error

    // MARK: - Typography

    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.semibold)
    static let title      = Font.system(.title, design: .default).weight(.semibold)
    static let headline   = Font.system(.headline, design: .default)
    static let body       = Font.system(.body, design: .default)
    static let caption    = Font.system(.caption, design: .default)
}

private extension Color {
    /// Build an opaque sRGB colour from a 0xRRGGBB literal.
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8)  & 0xFF) / 255.0,
                  blue:  Double( hex        & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}
```

- [ ] **Step 2: Build + test**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all 73 tests pass. (`MemoryPane` / `MenuBarContent` still reference `Theme.recording` / `.paused` / `.stopped` / `.cardBackground` / `.accent` etc. — all still defined, just with new values; the new tokens are added but not yet used.)

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/Theme.swift
git commit -m "MengoDesktop: Theme — adopt the mengo.ai dark brand palette + functional state colours"
```

---

## Task 2: `Brand.swift` + the logo asset + `build-mengo.sh`

**Files:**
- Create: `Sources/MengoDesktop/Brand.swift`
- Create: `Resources/MengoLogo.png` (copied)
- Modify: `build-mengo.sh`

- [ ] **Step 1: Copy the logo into `Resources/`**

```bash
cp ~/Desktop/Mengo.ai/public/logo.png Resources/MengoLogo.png
file Resources/MengoLogo.png   # → PNG image data, 1254 x 1254, RGBA
```

- [ ] **Step 2: Create `Brand.swift`**

Create `Sources/MengoDesktop/Brand.swift`:

```swift
import SwiftUI
import AppKit

/// Brand assets bundled with the app.
enum Brand {
    /// The mengo.ai mango logo (transparent PNG). `nil` when running via
    /// `swift run` rather than the assembled `.app` — callers fall back to
    /// text-only branding.
    static let logo: Image? = {
        guard let url = Bundle.main.url(forResource: "MengoLogo", withExtension: "png"),
              let nsImage = NSImage(contentsOf: url)
        else { return nil }
        return Image(nsImage: nsImage)
    }()
}
```

- [ ] **Step 3: Have `build-mengo.sh` copy the logo into the bundle**

In `build-mengo.sh`, in the "Assembling .app bundle" section — right after `cp Resources/MengoDesktopInfo.plist "$APP_BUNDLE/Contents/Info.plist"` and before the icon-generation block — add:

```bash
cp Resources/MengoLogo.png "$APP_BUNDLE/Contents/Resources/MengoLogo.png"
```

- [ ] **Step 4: Build + commit**

Run: `swift build --product MengoDesktop` → `Build complete!`

```bash
git add Sources/MengoDesktop/Brand.swift Resources/MengoLogo.png build-mengo.sh
git commit -m "MengoDesktop: bundle the mengo.ai mango logo (Brand.logo) + build-mengo.sh copies it into the .app"
```

---

## Task 3: Force the app to dark appearance

**Files:**
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift`

- [ ] **Step 1: Set `.darkAqua` in `applicationDidFinishLaunching`**

In `Sources/MengoDesktop/MengoDesktopApp.swift`, change `AppDelegate.applicationDidFinishLaunching` to:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Task { await AppDelegate.sharedRecorder?.start() }
    }
```

- [ ] **Step 2: Build + commit**

Run: `swift build --product MengoDesktop` → `Build complete!`

```bash
git add Sources/MengoDesktop/MengoDesktopApp.swift
git commit -m "MengoDesktop: force dark appearance (.darkAqua) at launch"
```

---

## Task 4: `MainWindowView` — logo wordmark header, accent selection, section crossfade

**Files:**
- Rewrite: `Sources/MengoDesktop/MainWindowView.swift`

- [ ] **Step 1: Replace `MainWindowView.swift`**

Overwrite `Sources/MengoDesktop/MainWindowView.swift`:

```swift
import SwiftUI

/// The main window: a logo-wordmark header over the section sidebar, with the
/// detail column showing the selected section's pane (real `MemoryPane` for
/// `.memory`, placeholders otherwise). Sidebar selection lives in `AppState`.
struct MainWindowView: View {
    let appState: AppState
    let recorder: RecorderController

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                wordmark
                List(selection: selectionBinding) {
                    ForEach(SidebarSection.allCases) { section in
                        Label {
                            HStack(spacing: 6) {
                                Text(section.displayName)
                                if let badge = section.badge {
                                    Spacer(minLength: 0)
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.mutedText)
                                }
                            }
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                        .tag(section)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Theme.windowBackground)
            .frame(minWidth: 200)
            .tint(Theme.accent)   // selection highlight in the brand orange
        } detail: {
            Group {
                switch appState.selectedSection {
                case .memory: MemoryPane(recorder: recorder)
                default:      ComingSoonPane(section: appState.selectedSection)
                }
            }
            .id(appState.selectedSection)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: appState.selectedSection)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            if let logo = Brand.logo {
                logo.resizable().scaledToFit().frame(width: 22, height: 22)
            }
            Text("Mengo").font(.title3.weight(.bold)).foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
    }

    private var selectionBinding: Binding<SidebarSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { if let newValue = $0 { appState.selectedSection = newValue } }
        )
    }
}
```

- [ ] **Step 2: Build + test**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all 73 tests pass.

> If the `.id()` + `.transition()` on the `NavigationSplitView` detail content doesn't animate cleanly (the framework can be finicky here), drop the `.transition`/`.animation`/`.id` and leave a plain swap — don't fight `NavigationSplitView`. The logo header and `.tint` are the load-bearing parts of this task.

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MainWindowView.swift
git commit -m "MengoDesktop: MainWindowView — logo wordmark header, brand-orange selection, dark sidebar, section crossfade"
```

---

## Task 5: `MemoryPane` — dark restyle, icons, animations

**Files:**
- Rewrite: `Sources/MengoDesktop/MemoryPane.swift`

- [ ] **Step 1: Replace `MemoryPane.swift`**

Overwrite `Sources/MengoDesktop/MemoryPane.swift`:

```swift
import SwiftUI

/// The Memory product's pane — the on-device recorder, at a glance. Dark brand
/// palette; SF Symbol icons on every action; animated status + stats.
struct MemoryPane: View {
    let recorder: RecorderController
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let msg = degradedMessage { degradedBanner(msg) }
                controls
                Divider().overlay(Theme.separator)
                sessionSection
                Divider().overlay(Theme.separator)
                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .background(
            LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground],
                           startPoint: .top, endPoint: .bottom)
        )
        .animation(.spring(duration: 0.35), value: degradedMessage)
        .task {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            while !Task.isCancelled {
                await recorder.refreshRecordingsSize()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder private var hero: some View {
        HStack(alignment: .top, spacing: 12) {
            heroDot.padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle).font(Theme.title).foregroundStyle(heroColor)
                if let subtitle = heroSubtitle {
                    Text(subtitle).font(Theme.body).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = heroDetail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: recorder.status)
    }

    @ViewBuilder private var heroDot: some View {
        switch recorder.status {
        case .recording:
            ZStack {
                Circle().fill(Theme.recording.opacity(0.20)).frame(width: 26, height: 26).blur(radius: 4)
                Image(systemName: "circle.fill").font(.system(size: 12))
                    .foregroundStyle(Theme.recording).symbolEffect(.pulse)
            }
        case .audioPaused, .screenPaused, .bothPaused:
            Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(Theme.paused)
        case .starting:
            ProgressView().controlSize(.small)
        case .idle:
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(Theme.mutedText)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.stopped)
        }
    }

    private var heroColor: Color {
        switch recorder.status {
        case .recording: return Theme.recording
        case .audioPaused, .screenPaused, .bothPaused: return Theme.paused
        case .error: return Theme.stopped
        case .starting, .idle: return Theme.primaryText
        }
    }

    private var heroTitle: String {
        switch recorder.status {
        case .idle: return "Not recording"
        case .starting: return "Starting…"
        case .recording: return "Recording"
        case .audioPaused: return "Audio paused"
        case .screenPaused: return "Screen paused"
        case .bothPaused: return "Paused"
        case .error: return "Recorder stopped"
        }
    }

    private var heroSubtitle: String? {
        switch recorder.status {
        case .recording:    return "Capturing your screen and microphone — everything stays on this Mac."
        case .audioPaused:  return "Still capturing your screen. Microphone capture is paused."
        case .screenPaused: return "Still capturing your microphone. Screen capture is paused."
        case .bothPaused:   return "Screen and microphone capture are both paused."
        case .starting:     return "Starting the on-device recorder…"
        case .idle:         return nil
        case .error(let m): return m
        }
    }

    private var heroDetail: String? {
        guard let since = recorder.recordingSince else { return nil }
        let clock = since.formatted(date: .omitted, time: .shortened)
        let up = recorder.lastHealth?.pipeline?.uptimeSecs ?? 0
        return "Since \(clock) · \(MemoryFormatting.duration(seconds: up))"
    }

    // MARK: - Degraded banner

    private var degradedMessage: String? {
        guard recorder.status == .recording, let h = recorder.lastHealth else { return nil }
        if h.frameStatus != "ok" { return "Screen capture is degraded — open the log for details." }
        if h.audioStatus != "ok" { return "Microphone capture is degraded — open the log for details." }
        return nil
    }

    private func degradedBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.paused)
            Text(msg).font(Theme.body).foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if case .error = recorder.status {
            Button { Task { await recorder.restartAfterCrash() } } label: {
                Label("Restart recorder", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        } else {
            HStack(spacing: 10) {
                Button { Task { await bothAction() } } label: {
                    Label(bothTitle, systemImage: recorder.status == .bothPaused ? "play.circle.fill" : "pause.circle.fill")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(disableControls)
                Button { Task { await audioAction() } } label: {
                    Label(audioTitle, systemImage: audioPausedNow ? "mic" : "mic.slash")
                }
                .buttonStyle(.bordered).disabled(disableControls)
                Button { Task { await screenAction() } } label: {
                    Label(screenTitle, systemImage: screenPausedNow ? "display" : "display.slash")
                }
                .buttonStyle(.bordered).disabled(disableControls)
                Spacer(minLength: 12)
                Button { NSWorkspace.shared.open(recorder.dataFolderURL) } label: {
                    Label("Reveal recordings", systemImage: "folder")
                }
                .buttonStyle(.link)
            }
        }
    }

    private var disableControls: Bool {
        switch recorder.status { case .starting, .idle, .error: return true; default: return false }
    }
    private var audioPausedNow: Bool { switch recorder.status { case .audioPaused, .bothPaused: return true; default: return false } }
    private var screenPausedNow: Bool { switch recorder.status { case .screenPaused, .bothPaused: return true; default: return false } }
    private var bothTitle: String { recorder.status == .bothPaused ? "Resume both" : "Pause both" }
    private var audioTitle: String { audioPausedNow ? "Resume audio" : "Pause audio" }
    private var screenTitle: String { screenPausedNow ? "Resume screen" : "Pause screen" }
    private func bothAction() async { recorder.status == .bothPaused ? await recorder.resumeAll() : await recorder.pauseAll() }
    private func audioAction() async { audioPausedNow ? await recorder.resumeAudio() : await recorder.pauseAudio() }
    private func screenAction() async { screenPausedNow ? await recorder.resumeScreen() : await recorder.pauseScreen() }

    // MARK: - This session

    @ViewBuilder private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This session").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack(spacing: 12) {
                StatTile(value: framesCaptured, label: "screens\ncaptured")
                StatTile(value: totalWords, label: "words\ntranscribed")
                StatTile(value: displayCount, label: "displays")
                StatTile(value: micCount, label: "mic\nsources")
            }
            HStack(spacing: 24) {
                if let last = lastCaptureText { metaLine("Last capture", last) }
                if let size = recorder.recordingsSizeBytes { metaLine("Recordings folder", MemoryFormatting.bytes(size)) }
            }
        }
        .opacity(recorder.status == .recording ? 1 : 0.55)
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        (Text(label + " · ").foregroundStyle(Theme.mutedText) + Text(value).foregroundStyle(Theme.secondaryText))
            .font(Theme.caption)
    }

    private var framesCaptured: Int? { recorder.lastHealth?.pipeline?.framesCaptured }
    private var totalWords: Int? { recorder.lastHealth?.audioPipeline?.totalWords }
    private var displayCount: Int? { recorder.lastHealth?.monitors?.count }
    private var micCount: Int? { recorder.lastHealth?.audioPipeline?.audioDevices?.filter { $0.lowercased().contains("input") }.count }

    private var lastCaptureText: String? {
        guard let s = recorder.lastHealth?.lastFrameTimestamp, let d = MemoryFormatting.parseTimestamp(s) else { return nil }
        return MemoryFormatting.relative(from: d)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mengo Memory keeps a private, on-device record of what you see and hear. Nothing is uploaded.")
                .font(Theme.caption).foregroundStyle(Theme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button { NSWorkspace.shared.open(recorder.recorderLogURL) } label: {
                Label("View log", systemImage: "doc.text")
            }
            .buttonStyle(.link).font(Theme.caption)
        }
    }
}

/// A "big number + small label" tile for the "This session" row. Rolls its
/// number with `.numericText`; lifts to `elevatedBackground` on hover.
private struct StatTile: View {
    let value: Int?
    let label: String
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.4), value: value)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center).fixedSize()
        }
        .frame(minWidth: 84)
        .padding(.vertical, 12).padding(.horizontal, 10)
        .background(hover ? Theme.elevatedBackground : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hover ? Theme.accentGlow : Theme.separator))
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.15), value: hover)
    }
}
```

- [ ] **Step 2: Build + test**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all 73 tests pass.

> Animation sanity: if any of these read as gimmicky on a real run — the breathing halo (`scaleEffect` + `repeatForever`), the fade-in `.offset`, the section crossfade — dial them back. The keepers are the `.symbolEffect(.pulse)` dot, the `.numericText()` roll, the hero status crossfade, the banner spring, and the tile hover lift.

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MemoryPane.swift
git commit -m "MengoDesktop: MemoryPane — dark restyle, SF Symbol icons on all actions, animated status + rolling stats"
```

---

## Task 6: `ComingSoonPane` glyph halo + `MenuBarContent` menu icons

**Files:**
- Modify: `Sources/MengoDesktop/ComingSoonPane.swift`
- Modify: `Sources/MengoDesktop/MenuBarContent.swift`

- [ ] **Step 1: Give `ComingSoonPane`'s glyph a soft accent halo**

In `Sources/MengoDesktop/ComingSoonPane.swift`, replace the glyph `Image(...)` line with a `ZStack` that puts an `accentGlow` circle behind it:

```swift
            ZStack {
                Circle().fill(Theme.accentGlow).frame(width: 110, height: 110).blur(radius: 14)
                Image(systemName: section.systemImage)
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
            }
```

(The rest of `ComingSoonPane` — the name, "Coming in Phase N", the blurb, `.background(Theme.paneBackground)` — is unchanged; it picks up the new dark `Theme` values automatically. Verify on a build that the text reads well on `paneBackground`.)

- [ ] **Step 2: Add SF Symbol icons to the menu's Memory group**

In `Sources/MengoDesktop/MenuBarContent.swift`:

(a) In `body`, change the post-pause Memory items to icon labels:

```swift
        if case .error = recorder.status {
            Button { Task { await recorder.restartAfterCrash() } } label: { Label("Restart recorder", systemImage: "arrow.clockwise") }
        }
        Button { NSWorkspace.shared.open(recorder.dataFolderURL) } label: { Label("Reveal recordings", systemImage: "folder") }
        Button { NSWorkspace.shared.open(recorder.recorderLogURL) } label: { Label("View log", systemImage: "doc.text") }
```

(b) Give `bothItem` / `audioItem` / `screenItem` icon labels too, e.g.:

```swift
    @ViewBuilder private var bothItem: some View {
        switch recorder.status {
        case .bothPaused:
            Button { Task { await recorder.resumeAll() } } label: { Label("Resume both", systemImage: "play.circle.fill") }
        case .recording, .audioPaused, .screenPaused:
            Button { Task { await recorder.pauseAll() } } label: { Label("Pause both", systemImage: "pause.circle.fill") }
        case .starting, .idle, .error:
            Button { } label: { Label("Pause both", systemImage: "pause.circle.fill") }.disabled(true)
        }
    }

    @ViewBuilder private var audioItem: some View {
        switch recorder.status {
        case .audioPaused, .bothPaused:
            Button { Task { await recorder.resumeAudio() } } label: { Label("Resume audio", systemImage: "mic") }
        default:
            Button { Task { await recorder.pauseAudio() } } label: { Label("Pause audio", systemImage: "mic.slash") }
                .disabled(!recorder.status.isRecording)
        }
    }

    @ViewBuilder private var screenItem: some View {
        switch recorder.status {
        case .screenPaused, .bothPaused:
            Button { Task { await recorder.resumeScreen() } } label: { Label("Resume screen", systemImage: "display") }
        default:
            Button { Task { await recorder.pauseScreen() } } label: { Label("Pause screen", systemImage: "display.slash") }
                .disabled(!recorder.status.isRecording)
        }
    }
```

(The Flow group, the nav buttons, `Quit`, and `MenuBarLabel` are unchanged — `MenuBarLabel`'s `Theme.recording`/`.paused`/`.stopped` references just resolve to the new colours.)

- [ ] **Step 3: Build + test**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all 73 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/MengoDesktop/ComingSoonPane.swift Sources/MengoDesktop/MenuBarContent.swift
git commit -m "MengoDesktop: ComingSoonPane glyph halo + SF Symbol icons on the menu's Memory items"
```

---

## Task 7: Update the smoke checklist + verify the build

**Files:**
- Modify: `docs/manual-smoke-tests/mengo-phase-2-memory.md`

- [ ] **Step 1: Refresh the "App behaviour" section**

In `docs/manual-smoke-tests/mengo-phase-2-memory.md`, add to (or fold into) the "App behaviour" list — the redesign items still apply; add:

```markdown
- [ ] The whole app is **dark** — window, sidebar, panes, and the menu-bar dropdown all on the `#121315`/`#17181B`/`#1D1F23` palette (not the system light theme).
- [ ] The **sidebar header** shows the mango logo + "Mengo" wordmark; the selected sidebar row is highlighted in the brand orange.
- [ ] Every action button has an **icon** — Pause both / Pause audio / Pause screen, Restart recorder, Reveal recordings, View log (pane *and* menu).
- [ ] The recording dot **pulses** and has a soft warm halo; the "This session" numbers **roll/count** when `/health` updates; switching sidebar sections **crossfades**; hovering a stat tile **lifts** it.
- [ ] Recorder states read as **green = recording**, **orange = paused**, **red = error** — in the hero, the menu-bar glyph, and the pane.
```

- [ ] **Step 2: Scriptable verification**

```bash
swift build
swift test
plutil -lint Resources/MengoDesktopInfo.plist
./build-mengo.sh   # confirms the logo + icns assembly still work; produces MengoDesktop.app
test -f MengoDesktop.app/Contents/Resources/MengoLogo.png && echo "logo bundled OK"
```
Expected: build complete; all 73 tests pass; plist OK; build script done; `logo bundled OK`.

- [ ] **Step 3: Commit**

```bash
git add docs/manual-smoke-tests/mengo-phase-2-memory.md
git commit -m "MengoDesktop: update smoke checklist for the dark theme / logo / icons / animations"
```

- [ ] **Step 4: (Eyeball) launch the app**

```bash
# quit any stale instance first so the new one can take port 3030:
osascript -e 'tell application "Mengo Desktop" to quit' 2>/dev/null; sleep 1
pkill -f "Helpers/screenpipe record" 2>/dev/null
open MengoDesktop.app
```
Walk the "App behaviour" checklist. (TCC/recording parts need a human at the machine, or the computer-use tools.)

---

## Done criteria

- `swift build` / `swift test` (73) pass; `./build-mengo.sh` still assembles the `.app` (now with `Contents/Resources/MengoLogo.png`).
- The app launches dark; the sidebar shows the mango-logo wordmark; the Memory pane and placeholder panes are on the dark palette; every action button has an icon; the recording dot pulses with a halo and the stat numbers roll; recorder state reads green / orange / red.
- `Sources/ScreenpipeMenu/` and `Sources/ScreenpipeFlow/` are untouched; only `MengoDesktop` files, `Resources/MengoLogo.png`, `build-mengo.sh`, and the smoke doc changed.
- The updated manual smoke checklist passes.
