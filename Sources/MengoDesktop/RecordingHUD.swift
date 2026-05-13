import SwiftUI
import AppKit

/// Manages the floating, non-activating HUD shown while a Flow recording is in
/// progress. Adapted from V1's `ScreenpipeFlow/RecordingHUD`. The panel never
/// becomes key — it won't steal focus from whatever the user is demonstrating —
/// floats above other windows on all Spaces, is draggable, and remembers its
/// last position.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    private static let originKey = "flow.hudOrigin"

    func show(session: FlowSession, onStop: @escaping () -> Void) {
        if panel != nil { return }
        let hosting = NSHostingView(rootView: RecordingHUDView(session: session, onStop: onStop))
        let size = NSSize(width: 340, height: 84)
        hosting.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .hudWindow, .titled],
                        backing: .buffered, defer: false)
        p.title = "Mengo Desktop"
        p.isFloatingPanel = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        p.setFrameOrigin(savedOrigin(forSize: size))
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        if let p = panel {
            UserDefaults.standard.set("\(p.frame.origin.x),\(p.frame.origin.y)", forKey: Self.originKey)
            p.close()
        }
        panel = nil
    }

    private func savedOrigin(forSize size: NSSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = s.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let pt = NSPoint(x: parts[0], y: parts[1])
                if NSScreen.screens.contains(where: { $0.frame.contains(pt) }) { return pt }
            }
        }
        if let f = NSScreen.main?.visibleFrame { return NSPoint(x: f.maxX - size.width - 20, y: f.maxY - size.height - 20) }
        return NSPoint(x: 200, y: 200)
    }
}

private struct RecordingHUDView: View {
    let session: FlowSession
    let onStop: () -> Void
    @State private var now: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.recording).frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(elapsedString).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(Theme.primaryText)
                    if let buf = bufferLabel { Text(buf).font(.caption).foregroundStyle(Theme.secondaryText) }
                }
                Text(hint).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Stop", action: onStop).keyboardShortcut(.return)
        }
        .padding(12)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var elapsedString: String {
        let s = max(0, Int(now.timeIntervalSince(session.activeRecordingStart)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    private var bufferLabel: String? {
        guard let bs = session.bufferRangeStart else { return nil }
        let s = max(0, Int(session.activeRecordingStart.timeIntervalSince(bs)))
        return "Buffer: \(s / 60)m \(s % 60)s"
    }
    private var hint: String {
        session.bufferRangeStart == nil
            ? "Narrate as you work."
            : "Narrate forward; you can also describe what happened earlier."
    }
}
