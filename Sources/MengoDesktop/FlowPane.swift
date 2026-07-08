import SwiftUI

/// The Flow product's pane — a small state machine: record a task, get a skill.
/// The floating HUD is the active control while recording; this pane is the
/// landing surface, the synthesizing spinner, the review UI, and the error state.
struct FlowPane: View {
    let flow: FlowController
    @State private var appeared = false

    var body: some View {
        Group {
            switch flow.flowState {
            case .idle:                  idle
            case .browsingTimeline:      TimelinePickerView(flow: flow)
            case .recording(let s):      recording(s)
            case .synthesizing:          synthesizing
            case .reviewing(let dir):    SkillReviewView(flow: flow, skillDir: dir)
            case .error(let msg):        errorView(msg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .opacity(appeared ? 1 : 0)
        .task { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
    }

    // MARK: idle

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mengo Flow").font(Theme.title).foregroundStyle(Theme.primaryText)
                    Text("Record a task once — narrating what you do — and Mengo turns it into a reusable agent skill.")
                        .font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { Task { await flow.start() } } label: { Label("Start recording", systemImage: "record.circle") }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    Text("⌃⌥R").font(Theme.caption).foregroundStyle(Theme.mutedText)
                    Spacer(minLength: 12)
                    Button { flow.beginBrowsingTimeline() } label: { Label("Grab last N minutes…", systemImage: "clock.arrow.circlepath") }
                        .buttonStyle(.bordered)
                    Text("⌃⌥G").font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
                if let note = flow.hotkeyNote {
                    Text(note).font(Theme.caption).foregroundStyle(Theme.paused)
                }
                Divider().overlay(Theme.separator)
                VStack(alignment: .leading, spacing: 10) {
                    Text("How it works").font(Theme.headline).foregroundStyle(Theme.primaryText)
                    step(1, "Start recording, then perform the task on your Mac — say out loud what you're doing and why. Call out anything that changes each time (“treat my email as a variable”).")
                    step(2, "Stop. Mengo asks \(flow.synthesisRuntimeDisplayName) to watch the recording and write a skill — SKILL.md, flow.json, key screenshots — into ~/.claude/skills/.")
                    step(3, "Review it, tweak the name and parameters, and Save. Your selected runtime can run it again on demand.")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18).background(Circle().fill(Theme.cardBackground)).overlay(Circle().stroke(Theme.separator))
            Text(text).font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: recording

    private func recording(_ session: FlowSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let s = max(0, Int(ctx.date.timeIntervalSince(session.activeRecordingStart)))
                    HStack(spacing: 12) {
                        Circle().fill(Theme.recording).frame(width: 12, height: 12).symbolEffect(.pulse)
                        Text("Recording").font(Theme.title).foregroundStyle(Theme.recording)
                        Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(.title2, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                    }
                }
                if let bs = session.bufferRangeStart {
                    let buf = max(0, Int(session.activeRecordingStart.timeIntervalSince(bs)))
                    Text("Buffer: \(buf / 60)m \(buf % 60)s — the synthesizer will reconstruct that earlier window from screen + accessibility.")
                        .font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
                Text(session.bufferRangeStart == nil
                     ? "Narrate your task as you go. Use the floating panel's Stop button (or ⌃⌥R) when you're done."
                     : "Narrate forward — and you can also describe what happened earlier. Stop with the floating panel or ⌃⌥R when you're done.")
                    .font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                Button { Task { await flow.stop() } } label: { Label("Stop recording", systemImage: "stop.circle") }
                    .buttonStyle(.bordered)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: synthesizing

    private var synthesizing: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Building your skill…").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text("\(flow.synthesisRuntimeDisplayName) is watching the recording — this usually takes 30 s–2 min. You can keep working; you'll get a notification when it's ready to review.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: error

    private func errorView(_ msg: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.stopped)
                    Text("Couldn't finish").font(Theme.headline).foregroundStyle(Theme.primaryText)
                }
                Text(msg).font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack(spacing: 10) {
                    Button { NSWorkspace.shared.open(logURL(from: msg)) } label: { Label("View log", systemImage: "doc.text") }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Button { Task { await flow.retrySynthesis() } } label: { Label("Retry", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    Button("Discard") { flow.discard() }.buttonStyle(.bordered)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func logURL(from message: String) -> URL {
        if let r = message.range(of: "(log: ", options: .backwards),
           let end = message.range(of: ")", range: r.upperBound..<message.endIndex) {
            return URL(fileURLWithPath: String(message[r.upperBound..<end.lowerBound]))
        }
        return Log.directory
    }
}
