# ScreenpipeMenu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app in Swift that auto-runs the screenpipe recorder while open, with pause/resume controls, and ships as a single `.app` coworkers can double-click.

**Architecture:** Single Swift Package Manager executable assembled into a `.app` bundle by `build.sh`. SwiftUI `MenuBarExtra` for UI. On first launch the app downloads the correct screenpipe binary from npm's registry into `~/Library/Application Support/ScreenpipeMenu/bin/`, then spawns it as a child process. App talks to the recorder's HTTP API on `127.0.0.1:3030` for health polling and audio pause/resume. Quitting the app kills the child.

**Tech Stack:** Swift 5.9+, SwiftUI (MenuBarExtra, macOS 13+), Foundation (`URLSession`, `Process`), `/usr/bin/tar` for extraction, `codesign` for ad-hoc signing.

**Spec:** `docs/superpowers/specs/2026-05-11-screenpipe-menubar-app-design.md`

**Working directory:** `/Users/kylebell/screenpipe`

**Testing philosophy:** TDD the pure-logic bits (arch detection, URL construction, version parsing). For integration-heavy code (HTTP client, child process, downloads), use manual smoke tests against a real running screenpipe. The spec's test section is the authoritative end-to-end checklist.

---

## File structure (final)

```
ScreenpipeMenu/
├── Package.swift
├── Sources/ScreenpipeMenu/
│   ├── ScreenpipeMenuApp.swift     ← @main, MenuBarExtra scene, menu UI
│   ├── AppState.swift              ← @Observable status, orchestration
│   ├── BinaryManager.swift         ← download + extract
│   ├── RecorderProcess.swift       ← spawn/kill child process
│   └── APIClient.swift             ← HTTP client (health, audio start/stop)
├── Tests/ScreenpipeMenuTests/
│   └── BinaryManagerTests.swift    ← unit tests for pure logic
├── Resources/
│   └── Info.plist                  ← copied into .app at build time
├── build.sh                        ← compile + assemble .app + sign + zip
├── README.md                       ← coworker instructions
└── .gitignore
```

---

## Task 1: Project scaffold + minimal menu bar app

**Files:**
- Create: `/Users/kylebell/screenpipe/Package.swift`
- Create: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/ScreenpipeMenuApp.swift`
- Create: `/Users/kylebell/screenpipe/.gitignore`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version:5.9
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
        )
    ]
)
```

- [ ] **Step 2: Create minimal app**

`Sources/ScreenpipeMenu/ScreenpipeMenuApp.swift`:

```swift
import SwiftUI

@main
struct ScreenpipeMenuApp: App {
    var body: some Scene {
        MenuBarExtra("Screenpipe", systemImage: "record.circle") {
            Text("ScreenpipeMenu — scaffolding")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 3: Create .gitignore**

```
.build/
.swiftpm/
DerivedData/
*.xcodeproj
ScreenpipeMenu.app/
ScreenpipeMenu.zip
*.dSYM
```

- [ ] **Step 4: Verify it compiles and runs**

Run: `cd /Users/kylebell/screenpipe && swift build`
Expected: compiles with no errors.

Run: `swift run ScreenpipeMenu &` — wait 2 seconds. Look at the top-right menu bar. You should see a small circle icon. Click it; you should see "ScreenpipeMenu — scaffolding" and "Quit". Click Quit.

If `swift run` complains about `MenuBarExtra` requiring an Info.plist with `LSUIElement`, that's fine for now — the Task 2 build script supplies it. The scaffolding test is just that it compiles.

- [ ] **Step 5: Commit**

```bash
cd /Users/kylebell/screenpipe
git init
git add Package.swift Sources .gitignore
git commit -m "scaffold: SPM package + minimal MenuBarExtra app"
```

---

## Task 2: build.sh + Info.plist → produces a runnable .app

**Files:**
- Create: `/Users/kylebell/screenpipe/Resources/Info.plist`
- Create: `/Users/kylebell/screenpipe/build.sh`

- [ ] **Step 1: Create Info.plist**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ScreenpipeMenu</string>
    <key>CFBundleIdentifier</key>
    <string>com.kylebell.screenpipemenu</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ScreenpipeMenu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Records microphone audio so screenpipe can transcribe what you say and hear.</string>
    <key>NSCameraUsageDescription</key>
    <string>Required by macOS screen capture on some systems.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Captures your screen so screenpipe can index what you see. Data stays on your Mac.</string>
</dict>
</plist>
```

- [ ] **Step 2: Create build.sh**

`build.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenpipeMenu"
BUNDLE_ID="com.kylebell.screenpipemenu"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"

cd "$PROJECT_DIR"

echo "==> Building universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc codesigning"
codesign --sign - --deep --force --options runtime "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

echo
echo "Done."
echo "  App:  $APP_BUNDLE"
echo "  Zip:  $ZIP_OUT"
```

- [ ] **Step 3: Make build.sh executable**

```bash
chmod +x /Users/kylebell/screenpipe/build.sh
```

- [ ] **Step 4: Verify the build produces a runnable .app**

```bash
cd /Users/kylebell/screenpipe && ./build.sh
```

Expected: completes without error, produces `ScreenpipeMenu.app` and `ScreenpipeMenu.zip`.

Manual verification:
1. `open /Users/kylebell/screenpipe/ScreenpipeMenu.app` — wait 2 seconds.
2. Look in the top-right menu bar — circle icon should appear.
3. Click it: "ScreenpipeMenu — scaffolding" and "Quit" visible.
4. No Dock icon should appear (LSUIElement working).
5. Click Quit. Menu bar icon disappears.

If the .app doesn't launch silently (Gatekeeper warning): in this session we built it on the same Mac, so it should run. If not, `xattr -d com.apple.quarantine ScreenpipeMenu.app` first.

- [ ] **Step 5: Commit**

```bash
git add Resources/ build.sh
git commit -m "build: .app bundle assembly via build.sh"
```

---

## Task 3: BinaryManager — pure-logic helpers (TDD)

These are the small testable units inside BinaryManager — arch detection, URL construction, version parsing. We TDD these because they're pure and easy to test in isolation; the I/O parts come in Task 4.

**Files:**
- Create: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/BinaryManager.swift`
- Create: `/Users/kylebell/screenpipe/Tests/ScreenpipeMenuTests/BinaryManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ScreenpipeMenuTests/BinaryManagerTests.swift`:

```swift
import XCTest
@testable import ScreenpipeMenu

final class BinaryManagerTests: XCTestCase {

    func testArchDetectionReturnsArm64OnAppleSilicon() {
        // We only test what the current machine is — CI matrix would handle both.
        // On Apple Silicon, expect "arm64". On Intel, expect "x64".
        let arch = BinaryManager.currentArch()
        XCTAssertTrue(arch == "arm64" || arch == "x64", "unexpected arch: \(arch)")
    }

    func testTarballURLForArm64() {
        let url = BinaryManager.tarballURL(version: "0.3.327", arch: "arm64")
        XCTAssertEqual(
            url.absoluteString,
            "https://registry.npmjs.org/@screenpipe/cli-darwin-arm64/-/cli-darwin-arm64-0.3.327.tgz"
        )
    }

    func testTarballURLForX64() {
        let url = BinaryManager.tarballURL(version: "0.3.327", arch: "x64")
        XCTAssertEqual(
            url.absoluteString,
            "https://registry.npmjs.org/@screenpipe/cli-darwin-x64/-/cli-darwin-x64-0.3.327.tgz"
        )
    }

    func testVersionParseExtractsLatestField() throws {
        let json = #"{"name":"screenpipe","version":"0.3.327","other":"ignored"}"#
        let data = json.data(using: .utf8)!
        let version = try BinaryManager.parseLatestVersion(from: data)
        XCTAssertEqual(version, "0.3.327")
    }

    func testVersionParseThrowsOnMissingField() {
        let data = #"{"name":"screenpipe"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try BinaryManager.parseLatestVersion(from: data))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (BinaryManager doesn't exist yet)**

```bash
cd /Users/kylebell/screenpipe && swift test 2>&1 | tail -10
```

Expected: compile failure — `cannot find 'BinaryManager' in scope`. That's the "failing test" — it doesn't compile yet.

- [ ] **Step 3: Create BinaryManager.swift with just the pure helpers**

`Sources/ScreenpipeMenu/BinaryManager.swift`:

```swift
import Foundation

enum BinaryManager {
    enum Error: Swift.Error {
        case versionFieldMissing
        case downloadFailed(statusCode: Int)
        case extractionFailed(stderr: String)
    }

    static func currentArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let cstr = raw.bindMemory(to: CChar.self).baseAddress!
            return String(cString: cstr)
        }
        return machine == "arm64" ? "arm64" : "x64"
    }

    static func tarballURL(version: String, arch: String) -> URL {
        URL(string: "https://registry.npmjs.org/@screenpipe/cli-darwin-\(arch)/-/cli-darwin-\(arch)-\(version).tgz")!
    }

    static func parseLatestVersion(from data: Data) throws -> String {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        else {
            throw Error.versionFieldMissing
        }
        return version
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test 2>&1 | tail -10
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenpipeMenu/BinaryManager.swift Tests/
git commit -m "BinaryManager: arch detection, URL construction, version parsing"
```

---

## Task 4: BinaryManager — download + extract (manual verification)

**Files:**
- Modify: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/BinaryManager.swift`

- [ ] **Step 1: Extend BinaryManager with I/O methods**

Append to `BinaryManager`:

```swift
extension BinaryManager {

    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScreenpipeMenu", isDirectory: true)
    }()

    static var binaryURL: URL { appSupportDir.appendingPathComponent("bin/screenpipe") }
    static var versionFileURL: URL { appSupportDir.appendingPathComponent("version.txt") }

    /// Returns the path to a runnable screenpipe binary, downloading on first call.
    /// Progress: 0.0 to 1.0 during download, called on an arbitrary queue.
    static func ensureBinary(progress: @escaping (Double) -> Void) async throws -> URL {
        if FileManager.default.isExecutableFile(atPath: binaryURL.path) {
            return binaryURL
        }

        try FileManager.default.createDirectory(at: appSupportDir.appendingPathComponent("bin"),
                                                withIntermediateDirectories: true)

        let version = try await fetchLatestVersion()
        let url = tarballURL(version: version, arch: currentArch())
        let tarballPath = appSupportDir.appendingPathComponent("screenpipe-\(version).tgz")
        try await download(from: url, to: tarballPath, progress: progress)
        try extract(tarball: tarballPath, into: appSupportDir.appendingPathComponent("bin"))
        try? FileManager.default.removeItem(at: tarballPath)
        try? versionFileURL.path.write(toFile: versionFileURL.path, atomically: true, encoding: .utf8)
        try? version.write(to: versionFileURL, atomically: true, encoding: .utf8)

        // Mark binary executable
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: binaryURL.path)

        return binaryURL
    }

    static func fetchLatestVersion() async throws -> String {
        let url = URL(string: "https://registry.npmjs.org/screenpipe/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Error.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try parseLatestVersion(from: data)
    }

    static func download(from url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: DownloadProgressDelegate(progress: progress))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Error.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    static func extract(tarball: URL, into directory: URL) throws {
        // The npm tarball layout is package/bin/{screenpipe, mlx.metallib}.
        // --strip-components=2 drops "package/bin/" so both files land directly in `directory`.
        // mlx.metallib must live next to the binary — the recorder loads it at runtime.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xzf", tarball.path, "-C", directory.path, "--strip-components=2", "package/bin/"]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Error.extractionFailed(stderr: err)
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    init(progress: @escaping (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
```

Note: the line `try? versionFileURL.path.write(...)` in the original draft is a copy-paste error — remove it. Final form should only have the second `version.write(to: versionFileURL, ...)`.

- [ ] **Step 2: Clean up the version-write duplicate**

In the snippet above, remove this incorrect line entirely:

```swift
try? versionFileURL.path.write(toFile: versionFileURL.path, atomically: true, encoding: .utf8)
```

Keep only:

```swift
try? version.write(to: versionFileURL, atomically: true, encoding: .utf8)
```

- [ ] **Step 3: Verify it compiles**

```bash
swift build 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 4: Manual smoke test — download flow**

Write a temporary main entry to test (or just exercise via REPL). Easiest: add a hidden test that downloads to a temp dir.

`Tests/ScreenpipeMenuTests/BinaryManagerTests.swift` — append:

```swift
    /// Network test. Only run manually; takes ~10-30 seconds and downloads ~150MB.
    func testRealDownload() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == nil,
                      "set RUN_NETWORK_TESTS=1 to enable")
        let version = try await BinaryManager.fetchLatestVersion()
        XCTAssertFalse(version.isEmpty)
        let arch = BinaryManager.currentArch()
        let url = BinaryManager.tarballURL(version: version, arch: arch)
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sp-test.tgz")
        try await BinaryManager.download(from: url, to: temp) { _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path))
        let size = try FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1_000_000) // at least 1 MB
        try? FileManager.default.removeItem(at: temp)
    }
```

Run: `RUN_NETWORK_TESTS=1 swift test --filter testRealDownload 2>&1 | tail -10`

Expected: passes within ~30s on a decent connection.

- [ ] **Step 5: Smoke test the full ensureBinary flow**

```bash
# Clear any cached binary first
rm -rf ~/Library/Application\ Support/ScreenpipeMenu

# Manual exercise via swift script (one-shot)
cat > /tmp/sp-bm-test.swift << 'EOF'
import Foundation
@_silgen_name("swift_demangleSymbol") func demangle() -> Void
EOF
```

Skip the inline script — easier to just test via a temporary entry point in the app. Add this temporary debug code to `ScreenpipeMenuApp.swift` at top of `body`, run, observe console, then revert:

```swift
// TEMPORARY DEBUG — remove after verifying
let _ = Task {
    do {
        let url = try await BinaryManager.ensureBinary { print("progress \($0)") }
        print("BINARY READY: \(url.path)")
    } catch {
        print("ERROR: \(error)")
    }
}
```

Build with `./build.sh`, run `open ScreenpipeMenu.app`, then `tail -f ~/Library/Logs/Console/*.log` or check Console.app for the print output. Verify the binary file appears at `~/Library/Application Support/ScreenpipeMenu/bin/screenpipe` and is executable (`ls -l` shows `-rwxr-xr-x`).

After verifying, REMOVE the temporary debug block.

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenpipeMenu/BinaryManager.swift Tests/ScreenpipeMenuTests/BinaryManagerTests.swift
git commit -m "BinaryManager: download + extract from npm registry"
```

---

## Task 5: APIClient — health + audio pause/resume

**Files:**
- Create: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/APIClient.swift`

- [ ] **Step 1: Create APIClient.swift**

```swift
import Foundation

actor APIClient {
    private let baseURL = URL(string: "http://127.0.0.1:3030")!
    private let token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    struct HealthStatus: Decodable {
        let status: String
        let frame_status: String
        let audio_status: String
    }

    enum APIError: Error {
        case badStatus(Int)
        case noResponse
    }

    func health() async throws -> HealthStatus {
        try await get("/health", as: HealthStatus.self)
    }

    func audioStop() async throws {
        try await post("/audio/stop")
    }

    func audioStart() async throws {
        try await post("/audio/start")
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: req)
        try check(response)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 3: Smoke test against the running screenpipe**

The screenpipe instance from earlier in this session is still running on port 3030 with token `sp-a6adc123`. (If not, restart it via `npx screenpipe@latest record` in a terminal.)

Add temporary debug code to test:

```swift
// TEMPORARY DEBUG — in ScreenpipeMenuApp body
let _ = Task {
    let client = APIClient(token: "sp-a6adc123")
    do {
        let h = try await client.health()
        print("HEALTH: \(h)")
        try await client.audioStop()
        print("AUDIO STOPPED")
        try await Task.sleep(for: .seconds(2))
        try await client.audioStart()
        print("AUDIO RESUMED")
    } catch {
        print("ERROR: \(error)")
    }
}
```

Build, run, check console. Expected: `HEALTH: HealthStatus(status: "healthy", ...)`, then audio stops and resumes. Remove the debug code.

- [ ] **Step 4: Commit**

```bash
git add Sources/ScreenpipeMenu/APIClient.swift
git commit -m "APIClient: health + audio pause/resume against 127.0.0.1:3030"
```

---

## Task 6: RecorderProcess — spawn / kill

**Files:**
- Create: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/RecorderProcess.swift`

- [ ] **Step 1: Create RecorderProcess.swift**

```swift
import Foundation

final class RecorderProcess {
    private var process: Process?
    private var logHandle: FileHandle?
    let token: String
    let logFileURL: URL

    init(token: String) {
        self.token = token
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ScreenpipeMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("recorder.log")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Spawn `binaryURL record` with our auth token set via env.
    func start(binaryURL: URL) throws {
        guard !isRunning else { return }

        // Truncate log file each start.
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logFileURL)
        self.logHandle = handle

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["record"]
        var env = ProcessInfo.processInfo.environment
        env["SCREENPIPE_API_KEY"] = token
        proc.environment = env
        proc.standardOutput = handle
        proc.standardError = handle

        try proc.run()
        self.process = proc
    }

    /// Send SIGTERM, wait up to 3s, then SIGKILL.
    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()  // SIGTERM
        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }
        try? logHandle?.close()
        logHandle = nil
        process = nil
    }

    static func newToken() -> String {
        let hex = (0..<8).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined()
        return "sp-\(hex)"
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 3: Smoke test spawn + kill**

Note: the long-running screenpipe from earlier may still occupy port 3030. Stop it first if so: `lsof -ti:3030 | xargs kill` (or quit the Bash background task).

Temporary debug:

```swift
let _ = Task {
    do {
        let bin = try await BinaryManager.ensureBinary { _ in }
        let rec = RecorderProcess(token: RecorderProcess.newToken())
        try rec.start(binaryURL: bin)
        print("STARTED, pid running: \(rec.isRunning)")
        try await Task.sleep(for: .seconds(15))
        let client = APIClient(token: rec.token)
        let h = try await client.health()
        print("HEALTH: \(h.status)")
        rec.stop()
        print("STOPPED, running: \(rec.isRunning)")
    } catch {
        print("ERR: \(error)")
    }
}
```

Build, run, check:
- After ~15s, console prints "HEALTH: healthy"
- After stop, `pgrep screenpipe` returns nothing
- `~/Library/Logs/ScreenpipeMenu/recorder.log` contains the recorder's startup banner

Remove debug code.

- [ ] **Step 4: Commit**

```bash
git add Sources/ScreenpipeMenu/RecorderProcess.swift
git commit -m "RecorderProcess: spawn with token, SIGTERM->SIGKILL on stop"
```

---

## Task 7: AppState — orchestrate everything

**Files:**
- Create: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/AppState.swift`

- [ ] **Step 1: Create AppState.swift**

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
        case starting
        case recording
        case audioPaused
        case visionPaused
        case bothPaused
        case error(String)

        var isRecording: Bool {
            switch self {
            case .recording, .audioPaused, .visionPaused, .bothPaused: return true
            default: return false
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var binaryVersion: String?

    private let recorder = RecorderProcess(token: RecorderProcess.newToken())
    private lazy var api = APIClient(token: recorder.token)
    private var healthTask: Task<Void, Never>?
    private var audioPaused = false
    private var visionPaused = false

    var logFileURL: URL { recorder.logFileURL }
    var dataFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screenpipe")
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        status = .downloading(progress: 0)
        do {
            let binaryURL = try await BinaryManager.ensureBinary { [weak self] p in
                Task { @MainActor in
                    self?.status = .downloading(progress: p)
                }
            }
            self.binaryVersion = (try? String(contentsOf: BinaryManager.versionFileURL).trimmingCharacters(in: .whitespacesAndNewlines))
            await start(binaryURL: binaryURL)
        } catch {
            status = .error("Setup failed: \(error)")
        }
    }

    private func start(binaryURL: URL) async {
        status = .starting
        audioPaused = false
        visionPaused = false
        do {
            try recorder.start(binaryURL: binaryURL)
        } catch {
            status = .error("Failed to start recorder: \(error)")
            return
        }
        startHealthPolling()
    }

    func quit() {
        healthTask?.cancel()
        recorder.stop()
        status = .idle
    }

    // MARK: - Pause / resume

    func pauseAudio() async {
        do {
            try await api.audioStop()
            audioPaused = true
            recomputeStatus()
        } catch {
            status = .error("Pause audio failed: \(error)")
        }
    }

    func resumeAudio() async {
        do {
            try await api.audioStart()
            audioPaused = false
            recomputeStatus()
        } catch {
            status = .error("Resume audio failed: \(error)")
        }
    }

    func pauseVision() {
        recorder.stop()
        visionPaused = true
        recomputeStatus()
        healthTask?.cancel()
    }

    func resumeVision() async {
        guard FileManager.default.isExecutableFile(atPath: BinaryManager.binaryURL.path) else {
            status = .error("Binary missing")
            return
        }
        visionPaused = false
        // Audio state will be re-applied after restart.
        let wasAudioPaused = audioPaused
        await start(binaryURL: BinaryManager.binaryURL)
        if wasAudioPaused {
            // Wait briefly for recorder to be up before pausing audio again.
            try? await Task.sleep(for: .seconds(8))
            await pauseAudio()
        }
    }

    func restartAfterCrash() async {
        recorder.stop()
        healthTask?.cancel()
        await start(binaryURL: BinaryManager.binaryURL)
    }

    func retryDownload() async {
        try? FileManager.default.removeItem(at: BinaryManager.appSupportDir)
        await bootstrap()
    }

    // MARK: - Health polling

    private func startHealthPolling() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }
            var failures = 0
            while !Task.isCancelled {
                do {
                    _ = try await self.api.health()
                    failures = 0
                    await MainActor.run { self.recomputeStatus() }
                } catch {
                    failures += 1
                    if failures >= 6 { // 30 s of failures
                        await MainActor.run {
                            self.status = .error("Recorder not responding")
                        }
                        return
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func recomputeStatus() {
        switch (audioPaused, visionPaused) {
        case (false, false): status = .recording
        case (true, false): status = .audioPaused
        case (false, true): status = .visionPaused
        case (true, true): status = .bothPaused
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/ScreenpipeMenu/AppState.swift
git commit -m "AppState: orchestrates download, start, health polling, pause/resume"
```

---

## Task 8: Full menu UI

**Files:**
- Modify: `/Users/kylebell/screenpipe/Sources/ScreenpipeMenu/ScreenpipeMenuApp.swift`

- [ ] **Step 1: Replace the scaffold with the full menu UI**

```swift
import SwiftUI
import AppKit

@main
struct ScreenpipeMenuApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: appState)
        } label: {
            Image(systemName: iconName(for: appState.status))
        }
        .menuBarExtraStyle(.menu)
    }

    private func iconName(for status: AppState.Status) -> String {
        switch status {
        case .idle: return "circle"
        case .downloading: return "arrow.down.circle"
        case .starting: return "circle.dotted"
        case .recording: return "record.circle.fill"
        case .audioPaused, .visionPaused, .bothPaused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

struct MenuView: View {
    let state: AppState

    var body: some View {
        Text(statusText)
            .font(.system(.body, design: .default).weight(.medium))

        if case .downloading(let p) = state.status {
            Text("\(Int(p * 100))% downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let v = state.binaryVersion {
            Text("screenpipe v\(v)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Pause/resume — visible only when recorder is up
        if state.status.isRecording {
            switch state.status {
            case .audioPaused, .bothPaused:
                Button("Resume audio") { Task { await state.resumeAudio() } }
            default:
                Button("Pause audio") { Task { await state.pauseAudio() } }
            }
            switch state.status {
            case .visionPaused, .bothPaused:
                Button("Resume screen") { Task { await state.resumeVision() } }
            default:
                Button("Pause screen") { state.pauseVision() }
            }
            Divider()
        }

        // Error recovery
        if case .error = state.status {
            Button("Restart recorder") { Task { await state.restartAfterCrash() } }
            Button("Retry download") { Task { await state.retryDownload() } }
            Divider()
        }

        // Standard items
        Button("Open data folder") {
            NSWorkspace.shared.open(state.dataFolderURL)
        }
        Button("Open log file") {
            NSWorkspace.shared.open(state.logFileURL)
        }
        Button("Open Privacy Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        Divider()
        Button("About ScreenpipeMenu") {
            let alert = NSAlert()
            alert.messageText = "ScreenpipeMenu"
            alert.informativeText = "Menu bar wrapper for screenpipe.\nhttps://github.com/screenpipe/screenpipe"
            alert.runModal()
        }
        Button("Quit") {
            state.quit()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .task {
            // Bootstrap on first appearance.
            if state.status == .idle {
                await state.bootstrap()
            }
        }
    }

    private var statusText: String {
        switch state.status {
        case .idle: return "Idle"
        case .downloading: return "Downloading screenpipe…"
        case .starting: return "Starting…"
        case .recording: return "● Recording"
        case .audioPaused: return "● Audio paused (screen recording)"
        case .visionPaused: return "● Screen paused (audio recording)"
        case .bothPaused: return "● Paused"
        case .error(let msg): return "⚠ \(msg)"
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 3: Build the .app and run end-to-end**

```bash
./build.sh
# Stop any existing screenpipe processes first
pkill -f "screenpipe record" 2>/dev/null || true
sleep 2
open ScreenpipeMenu.app
```

Manual verification against the spec's testing checklist:

1. **First-launch download** — if `~/Library/Application Support/ScreenpipeMenu/bin/screenpipe` exists from earlier testing, delete it: `rm -rf ~/Library/Application\ Support/ScreenpipeMenu`. Relaunch. Menu shows "Downloading screenpipe…" with %.
2. **Recording starts** — within ~30s, status row becomes "● Recording" green-ish (icon turns to record.circle.fill).
3. **Pause audio** — click. Status row "● Audio paused (screen recording)". `curl http://127.0.0.1:3030/health -H "Authorization: Bearer ..."` shows audio chunks not incrementing.
4. **Pause screen** — click. Status "● Screen paused (audio recording)". `pgrep screenpipe` returns nothing.
5. **Resume screen** — click. Within ~15s, status back to recording.
6. **Quit** — click Quit. `pgrep screenpipe` empty.
7. **Crash recovery** — relaunch app, wait for recording state, then `pkill -9 -f "screenpipe record"`. Within 30s, menu shows error and "Restart recorder" item appears. Click it; verify recovery.

If any step fails, debug, fix, recommit before moving on.

- [ ] **Step 4: Commit**

```bash
git add Sources/ScreenpipeMenu/ScreenpipeMenuApp.swift
git commit -m "ScreenpipeMenuApp: full menu UI with pause/resume + recovery"
```

---

## Task 9: README + final distribution build

**Files:**
- Create: `/Users/kylebell/screenpipe/README.md`

- [ ] **Step 1: Write README.md**

````markdown
# ScreenpipeMenu

A tiny macOS menu bar app that runs [screenpipe](https://github.com/screenpipe/screenpipe) while it's open. Local-only AI memory of your screen and mic. No Node, no Terminal — double-click and go.

## Install (coworkers, read this)

1. Download `ScreenpipeMenu.zip` and unzip.
2. **First launch only:** right-click `ScreenpipeMenu.app` → **Open** → click **Open** in the dialog. (macOS Gatekeeper blocks unsigned apps until you tell it once.)
3. The first time it runs it'll download the screenpipe binary (~150 MB). You'll see "Downloading…" in the menu bar with a percentage.
4. macOS will prompt for **Screen Recording** and **Microphone** permission. Grant both in System Settings → Privacy & Security, then quit and relaunch the app.
5. The app lives in the top-right menu bar (record icon). Click it for status and controls.

## Menu

- **Pause audio** — stops microphone capture without restarting. Resumes instantly.
- **Pause screen** — stops the recorder entirely. Resumes in ~15 s (re-initializes models).
- **Open data folder** — `~/.screenpipe`. Everything is here, local.
- **Open log file** — `~/Library/Logs/ScreenpipeMenu/recorder.log`.
- **Open Privacy Settings** — fast path to the macOS panel.
- **Quit** — stops recording and exits.

## Build from source

```bash
git clone <this repo> ScreenpipeMenu
cd ScreenpipeMenu
./build.sh
open ScreenpipeMenu.app
```

`build.sh` produces `ScreenpipeMenu.app` and `ScreenpipeMenu.zip` (the shareable one).

## Specs

- macOS 13+ (Ventura or later)
- ~150 MB binary download on first launch
- 5-10% CPU, 0.5-3 GB RAM while recording
- ~20 GB/month storage (configurable in screenpipe itself)
- 100% local; nothing leaves the Mac
````

- [ ] **Step 2: Build the final distribution zip**

```bash
cd /Users/kylebell/screenpipe && ./build.sh
ls -la ScreenpipeMenu.zip
```

Expected: a single `.zip` ready to share.

- [ ] **Step 3: Coworker simulation test**

Test as a fresh user would receive it:

```bash
# Simulate "downloaded from internet" by setting the quarantine flag
xattr -w com.apple.quarantine "0181;0000;Safari;|com.apple.Safari" ScreenpipeMenu.app

# Try to open it normally — should be blocked by Gatekeeper
open ScreenpipeMenu.app
```

Expected: macOS shows "ScreenpipeMenu can't be opened" or "cannot verify" dialog. This is correct behavior — confirms the README's right-click → Open step is necessary.

Now do the actual user flow: in Finder, right-click `ScreenpipeMenu.app` → **Open** → confirm the dialog. App should launch normally.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README with install/build instructions"
```

- [ ] **Step 5: Final tag**

```bash
git tag v1.0.0
```

Done. `ScreenpipeMenu.zip` is ready to send.

---

## Self-review

**Spec coverage:**
- Menu bar app with `LSUIElement=true` — Task 2 Info.plist ✓
- Download on first launch from npm registry — Task 3, 4 ✓
- Quit stops recorder (SIGTERM→SIGKILL) — Task 6 stop(), Task 7 quit() ✓
- Unsigned + ad-hoc codesign — Task 2 build.sh ✓
- Pause audio (API) + Pause screen (process restart) — Task 7 + Task 8 ✓
- Menu items per spec (data folder, logs, privacy, retry/restart, about, quit) — Task 8 ✓
- Status dot color & icon variants — Task 8 iconName() ✓
- Error handling for download fail, crash, port-in-use, permissions — Task 7 error states + Task 8 menu items + recomputeStatus ✓
- Distribution README — Task 9 ✓
- Universal binary — Task 2 build.sh `--arch arm64 --arch x86_64` ✓

**Placeholder scan:**
- "TBD" / "TODO" — none in plan body. The temporary debug blocks are explicitly marked and the steps say "remove after verifying". OK.
- "Similar to Task N" — none.
- Test code in every TDD step — Task 3 has actual XCTest code. Tasks 4-8 use manual verification because they're heavily I/O-bound; this is called out in the plan header.

**Type consistency:**
- `BinaryManager.binaryURL`, `BinaryManager.versionFileURL`, `BinaryManager.appSupportDir` — same names in Tasks 4, 7, 8 ✓
- `RecorderProcess.token`, `start(binaryURL:)`, `stop()`, `isRunning`, `newToken()` — consistent across Tasks 6, 7 ✓
- `APIClient.health()`, `audioStart()`, `audioStop()` — consistent Tasks 5, 7 ✓
- `AppState.Status` cases — defined Task 7, used Task 8 ✓
- `AppState.bootstrap()`, `quit()`, `pauseAudio()`, `resumeAudio()`, `pauseVision()`, `resumeVision()`, `restartAfterCrash()`, `retryDownload()` — defined Task 7, called Task 8 ✓
