import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedState: AppState?
    @MainActor static weak var sharedController: RecordingController?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.sharedState?.writeRecoveryIfNeeded()
            Logger.log("app terminating")
        }
    }
}

extension Notification.Name {
    static let openLibrary = Notification.Name("ScreenpipeFlow.openLibrary")
}

@main
@MainActor
struct ScreenpipeFlowApp: App {
    @State private var appState: AppState
    @State private var hotkeys: HotkeyManager
    @State private var controller: RecordingController
    @State private var hud: RecordingHUDController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Logger.bootstrap()
        let state = AppState()
        let ctrl = RecordingController(state: state)
        let hk = HotkeyManager()
        let h = RecordingHUDController()

        _appState = State(initialValue: state)
        _controller = State(initialValue: ctrl)
        _hotkeys = State(initialValue: hk)
        _hud = State(initialValue: h)

        AppDelegate.sharedState = state
        AppDelegate.sharedController = ctrl

        hk.register(HotkeyManager.recordToggle) {
            Task { @MainActor in
                guard let state = AppDelegate.sharedState,
                      let ctrl = AppDelegate.sharedController else { return }
                switch state.sessionState {
                case .recording: await ctrl.stop()
                case .idle: await ctrl.startProactive()
                default: break
                }
            }
        }
        hk.register(HotkeyManager.grabLast) {
            Task { @MainActor in
                AppDelegate.sharedState?.beginBrowsingTimeline()
            }
        }

        // One-shot: surface any leftover interrupted-recording marker.
        // Runs synchronously in init — the NSAlert blocks the menu bar from
        // appearing until dismissed, which is the desired UX.
        if let interruptedAt = state.loadMostRecentInterruptedStart() {
            let alert = NSAlert()
            let fmt = DateFormatter()
            fmt.dateStyle = .none
            fmt.timeStyle = .medium
            alert.messageText = "An earlier recording was interrupted"
            alert.informativeText = """
            ScreenpipeFlow detected that a recording started at \
            \(fmt.string(from: interruptedAt)) was interrupted. \
            Use "Grab last N minutes" from the menu and scroll back to \
            that time to recover the demonstration.
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
            state.clearRecoveryMarkers()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: appState, controller: controller)
        } label: {
            // The label is the only View that's always in the scene tree
            // (the dropdown only exists when open). State-driven side effects
            // therefore have to attach here: onChange and the one-time observer
            // setup. Wrapping in a Group so modifiers attach to a stable view.
            Group {
                HStack(spacing: 4) {
                    Text(StatusBarLabel.text(for: appState.sessionState))
                    Image(systemName: StatusBarLabel.iconName(for: appState.sessionState))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(StatusBarLabel.color(for: appState.sessionState))
                }
                .foregroundStyle(StatusBarLabel.color(for: appState.sessionState))
            }
            .onChange(of: appState.sessionState) { _, new in
                handleSessionStateChange(new)
            }
            .task {
                // Runs ONCE when the label first appears (the label is created
                // once at app launch and lives until quit).
                NotificationCenter.default.addObserver(
                    forName: .openLibrary, object: nil, queue: .main
                ) { _ in
                    Task { @MainActor in openWindow(id: "library") }
                }
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Timeline", id: "timeline") {
            if case .browsingTimeline = appState.sessionState {
                TimelineWindow(state: appState, controller: controller)
            } else {
                Text("Open this window from the menu (\"Grab last N minutes…\").")
                    .padding(40)
            }
        }
        .windowResizability(.contentSize)

        Window("Review", id: "review") {
            if case .reviewing(let url) = appState.sessionState {
                ReviewWindow(state: appState, controller: controller, skillDir: url)
            } else {
                Text("No skill ready for review.").padding(40)
            }
        }
        .windowResizability(.contentSize)

        Window("Library", id: "library") {
            LibraryWindow(state: appState)
        }
        .windowResizability(.contentSize)
    }

    private func handleSessionStateChange(_ new: AppState.SessionState) {
        Logger.log("session state -> \(new)")
        switch new {
        case .idle:
            hud.hide()
            dismissWindow(id: "timeline")
            // Don't dismiss review — user may want to keep reviewing past skills.
        case .browsingTimeline:
            hud.hide()
            dismissWindow(id: "review")
            openWindow(id: "timeline")
            NSApp.activate(ignoringOtherApps: true)
        case .recording(let session):
            dismissWindow(id: "timeline")
            dismissWindow(id: "review")
            hud.show(session: session) {
                Task { @MainActor in await controller.stop() }
            }
        case .synthesizing:
            hud.hide()
            dismissWindow(id: "timeline")
        case .reviewing:
            hud.hide()
            dismissWindow(id: "timeline")
            openWindow(id: "review")
            NSApp.activate(ignoringOtherApps: true)
        case .error:
            hud.hide()
        }
    }
}

// MARK: - Status bar label helpers

enum StatusBarLabel {
    static func text(for state: AppState.SessionState) -> String {
        switch state {
        case .idle: return "Flow"
        case .browsingTimeline: return "Pick start"
        case .recording: return "● Rec"
        case .synthesizing: return "Synth…"
        case .reviewing: return "Review"
        case .error: return "Error"
        }
    }

    static func color(for state: AppState.SessionState) -> Color {
        switch state {
        case .recording: return .red
        case .synthesizing: return .blue
        case .reviewing: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    static func iconName(for state: AppState.SessionState) -> String {
        switch state {
        case .idle, .browsingTimeline: return "waveform.circle"
        case .recording: return "circle.fill"
        case .synthesizing: return "ellipsis.circle"
        case .reviewing: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Menu bar dropdown

struct MenuView: View {
    let state: AppState
    let controller: RecordingController

    var body: some View {
        Text("ScreenpipeFlow").font(.headline)
        statusLine
        Divider()

        switch state.sessionState {
        case .idle:
            Button("Start recording  ⌃⌥R") {
                Task { await controller.startProactive() }
            }
            Button("Grab last 5 minutes…  ⌃⌥G") {
                state.beginBrowsingTimeline()
            }

        case .recording:
            Button("Stop recording  ⌃⌥R") {
                Task { await controller.stop() }
            }

        case .browsingTimeline:
            Button("Cancel timeline picker") {
                state.cancelBrowsingTimeline()
            }

        case .synthesizing:
            Text("Synthesizing skill — you'll see a Review window when ready.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .reviewing:
            Text("Skill ready — see the Review window.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .error(let msg):
            Text("⚠ \(msg)").foregroundStyle(.red).lineLimit(3)
            Button("Dismiss") { state.finalize() }
        }

        Divider()
        Button("Open library") {
            NotificationCenter.default.post(name: .openLibrary, object: nil)
        }
        Button("Open skills folder") {
            NSWorkspace.shared.open(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/skills"))
        }
        Button("Open app log") {
            NSWorkspace.shared.open(Logger.appLogURL)
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.sessionState {
        case .idle:
            Text("Idle").font(.caption).foregroundStyle(.secondary)
        case .browsingTimeline:
            Text("Pick a start point in the timeline window")
                .font(.caption).foregroundStyle(.secondary)
        case .recording:
            Text("● Recording").font(.caption).foregroundStyle(.red)
        case .synthesizing:
            Text("Synthesizing…").font(.caption).foregroundStyle(.blue)
        case .reviewing:
            Text("Skill ready for review")
                .font(.caption).foregroundStyle(.green)
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(3)
        }
    }
}
