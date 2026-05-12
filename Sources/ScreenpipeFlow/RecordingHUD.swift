import SwiftUI
import AppKit

/// Manages a single floating HUD window during a recording session.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?

    func show(session: RecordingSession, onStop: @escaping () -> Void) {
        if panel != nil { return }
        let hosting = NSHostingView(rootView: RecordingHUDView(session: session, onStop: onStop))
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 80)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 80),
            styleMask: [.nonactivatingPanel, .hudWindow, .titled],
            backing: .buffered,
            defer: false
        )
        p.title = "ScreenpipeFlow"
        p.isFloatingPanel = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.contentView = hosting
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 360, y: f.maxY - 100))
        } else {
            p.center()
        }
        p.orderFrontRegardless()
        self.panel = p
    }

    func hide() {
        panel?.close()
        panel = nil
    }
}

private struct RecordingHUDView: View {
    let session: RecordingSession
    let onStop: () -> Void
    @State private var now: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(elapsedString)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if let buf = bufferLabel {
                        Text(buf).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Stop", action: onStop)
                .keyboardShortcut(.return)
        }
        .padding(12)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { d in
            now = d
        }
    }

    private var elapsedString: String {
        let s = Int(now.timeIntervalSince(session.activeRecordingStart))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var bufferLabel: String? {
        guard let bs = session.bufferRangeStart else { return nil }
        let s = Int(session.activeRecordingStart.timeIntervalSince(bs))
        return "Buffer: \(s / 60)m \(s % 60)s"
    }

    private var hint: String {
        session.bufferRangeStart == nil
            ? "Narrate what you're doing."
            : "Narrate forward; you can also describe what happened earlier."
    }
}
