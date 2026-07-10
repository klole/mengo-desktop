import SwiftUI
import AppKit

/// The Flow product's pane: demonstrate a task, get a reusable skill.
struct FlowPane: View {
    let flow: FlowController
    let recorder: RecorderController
    let settings: SettingsStore
    @State private var appeared = false
    @State private var showingSources = false
    @State private var showingOutputTarget = false
    @State private var showingGuide = false
    @State private var extractionDetail: ExtractionDetail?

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
        .sheet(isPresented: $showingSources) {
            RecordingSourcesView(recorder: recorder)
        }
        .sheet(isPresented: $showingOutputTarget) {
            FlowOutputTargetSheet(settings: settings)
        }
        .sheet(isPresented: $showingGuide) {
            FlowGuideSheet()
        }
        .sheet(item: $extractionDetail) { detail in
            FlowExtractionDetailSheet(detail: detail)
        }
    }

    // MARK: Idle

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                flowHeader
                flowControlStrip
                if let note = flow.hotkeyNote {
                    Text(note).font(Theme.caption).foregroundStyle(Theme.paused)
                }

                GeometryReader { proxy in
                    if proxy.size.width >= 1100 {
                        HStack(alignment: .top, spacing: 14) {
                            flowMainColumn
                            flowRightRail.frame(width: 300)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            flowMainColumn
                            flowRightRail
                        }
                    }
                }
                .frame(minHeight: 650)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var flowHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mengo Flow").font(Theme.title).foregroundStyle(Theme.primaryText)
            Text("Demonstrate a task once — narrate what you do — and Mengo turns it into a reusable skill.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var flowControlStrip: some View {
        ViewThatFits(in: .horizontal) {
            wideControlStrip
            mediumControlStrip
            compactControlStrip
        }
        .padding(10)
        .background(cardBackground(cornerRadius: 10))
    }

    @ViewBuilder private var wideControlStrip: some View {
        HStack(spacing: 0) {
            startDemonstratingButton
            keycap("⌃⌥R").padding(.horizontal, 10)
            grabLastButton(title: "Grab Last 5 Min")
            keycap("⌃⌥G").padding(.leading, 10)
            stripDivider
            settingsStripItems
        }
    }

    @ViewBuilder private var mediumControlStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                startDemonstratingButton
                grabLastButton(title: "Grab Last")
                stripDivider
                settingsStripItems
            }
            shortcutRow
        }
    }

    @ViewBuilder private var compactControlStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                startDemonstratingButton
                grabLastButton(title: "Grab Last")
            }
            shortcutRow
            VStack(alignment: .leading, spacing: 10) {
                stripButton(icon: "display", title: "Select Monitor", value: monitorSummary, chevron: true) { showingSources = true }
                Divider().overlay(Theme.separator)
                stripButton(icon: "waveform", title: "Audio Source", value: audioSummary, chevron: true) { showingSources = true }
                Divider().overlay(Theme.separator)
                stripButton(icon: "sparkles", title: "Target LLM / Output", value: settings.synthesisRuntime.displayName, chevron: true, accent: Color(flowHex: 0xA970FF)) { showingOutputTarget = true }
            }
        }
    }

    private var startDemonstratingButton: some View {
        Button { Task { await flow.start() } } label: {
            HStack(spacing: 9) {
                Image(systemName: "record.circle").font(.system(size: 14, weight: .semibold))
                Text("Start Demonstrating").font(Theme.headline).lineLimit(1)
            }
            .frame(minWidth: 188)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
        }
        .buttonStyle(.plain)
    }

    private func grabLastButton(title: String) -> some View {
        Button { flow.beginBrowsingTimeline() } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .medium))
                Text(title).font(Theme.body).lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.primaryText)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var settingsStripItems: some View {
        HStack(spacing: 0) {
            stripButton(icon: "display", title: "Select Monitor", value: monitorSummary, chevron: true) { showingSources = true }
            stripDivider
            stripButton(icon: "waveform", title: "Audio Source", value: audioSummary, chevron: true) { showingSources = true }
            stripDivider
            stripButton(icon: "sparkles", title: "Target LLM / Output", value: settings.synthesisRuntime.displayName, chevron: true, accent: Color(flowHex: 0xA970FF)) { showingOutputTarget = true }
        }
    }

    @ViewBuilder private var shortcutRow: some View {
        HStack(spacing: 12) {
            shortcutHint(label: "Start Demonstrating", keys: "⌃⌥R")
            shortcutHint(label: "Grab last 5 minutes", keys: "⌃⌥G")
        }
    }

    private func shortcutHint(label: String, keys: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            keycap(keys)
        }
    }

    @ViewBuilder private var flowMainColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            teachCard
            jumpBackCard
            emptySkillsCard
        }
    }

    @ViewBuilder private var teachCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                FlowTeachingOrb().frame(width: 210, height: 210)
                teachCopy(showAllLessons: true)
            }
            VStack(alignment: .center, spacing: 18) {
                FlowTeachingOrb().frame(width: 156, height: 156)
                teachCopy(showAllLessons: false)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                cardBackground(cornerRadius: 10)
                FlowStarfield().opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
    }

    private func teachCopy(showAllLessons: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Teach Mengo a new skill")
                    .font(.system(size: showAllLessons ? 28 : 24, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Text("Start demonstrating and show Mengo how to complete a task.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            }

            if showAllLessons {
                HStack(alignment: .top, spacing: 22) {
                    flowLesson(icon: "speaker.wave.2.fill", title: "Show your process", body: "Speak out loud and do the task naturally.", color: Theme.accent)
                    flowLesson(icon: "sparkles", title: "AI learns & structures", body: "Mengo watches, understands, and extracts the logic.", color: Color(flowHex: 0xA970FF))
                    flowLesson(icon: "shippingbox.fill", title: "Reusable skill", body: "Get a clean skill you can run anytime.", color: Color(flowHex: 0x5D6DFF))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    flowLesson(icon: "speaker.wave.2.fill", title: "Show your process", body: "Speak out loud and do the task naturally.", color: Theme.accent)
                    flowLesson(icon: "sparkles", title: "AI learns & structures", body: "Mengo watches and extracts the logic.", color: Color(flowHex: 0xA970FF))
                }
            }

            tipsForBestResults
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tipsForBestResults: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Color(flowHex: 0x8D7CFF))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(flowHex: 0x302653)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Tips for best results").font(Theme.caption).foregroundStyle(Theme.primaryText)
                Text("Narrate decisions, call out variables, and highlight key steps.")
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button { showingGuide = true } label: {
                HStack(spacing: 5) {
                    Text("View guide")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardBackground.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var jumpBackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jump back in").font(Theme.headline).foregroundStyle(Theme.primaryText)
                Text("Continue a draft or start a new demonstration.")
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { jumpBackCards }
                VStack(spacing: 12) { jumpBackCards }
            }
        }
        .padding(16)
        .background(cardBackground(cornerRadius: 10))
    }

    @ViewBuilder private var jumpBackCards: some View {
        let hasDraft = flow.library.first != nil
        jumpActionCard(
            icon: "play.rectangle",
            title: flow.library.first?.name ?? "Continue last demo",
            body: hasDraft ? "Created \(MemoryFormatting.relative(from: flow.library.first!.createdAt))" : "No draft is waiting yet.",
            button: hasDraft ? "Continue" : "No draft",
            color: Color(flowHex: 0xA970FF),
            isEnabled: hasDraft
        ) { if let first = flow.library.first { flow.reopenInReview(slug: first.slug) } }

    }

    @ViewBuilder private var emptySkillsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(flow.library.isEmpty ? "Your skills will appear here once you start demonstrating." : "\(flow.library.count) skill\(flow.library.count == 1 ? "" : "s") ready")
                .font(Theme.body)
                .foregroundStyle(Theme.primaryText)
            Text(flow.library.isEmpty ? "Each demonstration is saved as a draft and can be turned into a reusable skill." : "Open the Library tab to review, reopen, or delete saved skills.")
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(cardBackground(cornerRadius: 10))
    }

    @ViewBuilder private var flowRightRail: some View {
        VStack(spacing: 12) {
            livePreviewCard
            extractionCard
            outputTargetCard
        }
    }

    @ViewBuilder private var livePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live Flow Preview").font(Theme.headline).foregroundStyle(Theme.primaryText)
                Spacer()
                Text("Ready")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.recording)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.recording.opacity(0.12)))
            }
            VStack(spacing: 9) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.secondaryText)
                Text("Nothing recording yet").font(Theme.caption).foregroundStyle(Theme.primaryText)
                Text("Start demonstrating to see transcript, actions, and AI insights here.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await flow.start() } }
            .frame(maxWidth: .infinity, minHeight: 135)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.windowBackground.opacity(0.32))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            )
        }
        .padding(16)
        .background(cardBackground(cornerRadius: 10))
    }

    @ViewBuilder private var extractionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Will Extract").font(Theme.headline).foregroundStyle(Theme.primaryText)
            extractionRow(.steps)
            extractionRow(.variables)
            extractionRow(.decisions)
            extractionRow(.apps)
            extractionRow(.actions)
        }
        .padding(16)
        .background(cardBackground(cornerRadius: 10))
    }

    @ViewBuilder private var outputTargetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Output Target").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(flowHex: 0xC191FF))
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color(flowHex: 0x2C2145)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.synthesisRuntime.displayName).font(Theme.body).foregroundStyle(Theme.primaryText)
                    Text(outputTargetDescription)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Button("Change") { showingOutputTarget = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(flowHex: 0x211936), Theme.cardBackground], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(flowHex: 0x3C2B66), lineWidth: 1))
        )
    }

    // MARK: Recording

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

    // MARK: Synthesizing

    private var synthesizing: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Building your skill…").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text("Claude Code is watching the recording — this usually takes 30 s–2 min. You can keep working; you'll get a notification when it's ready to review.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error

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

    private var stripDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 44)
            .padding(.horizontal, 10)
    }

    private func stripItem(icon: String, title: String, value: String, chevron: Bool, accent: Color = Theme.secondaryText) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.caption).foregroundStyle(Theme.primaryText)
                Text(value).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.mutedText)
            }
        }
        .frame(minWidth: 155, alignment: .leading)
    }

    private func stripButton(icon: String, title: String, value: String, chevron: Bool, accent: Color = Theme.secondaryText, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            stripItem(icon: icon, title: title, value: value, chevron: chevron, accent: accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.windowBackground.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator, lineWidth: 1))
    }

    private func flowLesson(icon: String, title: String, body: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(color.opacity(0.16)))
                Text(title).font(Theme.caption).foregroundStyle(Theme.primaryText).lineLimit(1)
            }
            Text(body)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func jumpActionCard(icon: String, title: String, body: String, button: String, color: Color, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(color.opacity(isEnabled ? 1.0 : 0.55))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(isEnabled ? 0.16 : 0.08)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(Theme.body).foregroundStyle(isEnabled ? Theme.primaryText : Theme.secondaryText).lineLimit(2)
                    Text(body).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }
            Button(button, action: action)
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1.0 : 0.72)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
        )
    }

    private func extractionRow(_ detail: ExtractionDetail) -> some View {
        Button {
            extractionDetail = detail
        } label: {
            HStack(spacing: 12) {
                Image(systemName: detail.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(detail.color)
                    .frame(width: 31, height: 31)
                    .background(RoundedRectangle(cornerRadius: 7).fill(detail.color.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.title).font(Theme.body).foregroundStyle(Theme.primaryText)
                    Text(detail.body).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.mutedText)
            }
        }
        .buttonStyle(.plain)
    }

    private var monitorSummary: String {
        if let ids = recorder.runningMonitorIDs {
            if ids.isEmpty { return "No displays" }
            return ids.count == 1 ? "1 display" : "\(ids.count) displays"
        }
        let monitors = recorder.lastHealth?.monitors ?? []
        if monitors.isEmpty { return "All displays" }
        if monitors.count == 1 { return monitors[0].components(separatedBy: " (").first ?? monitors[0] }
        return "\(monitors.count) displays"
    }

    private var audioSummary: String {
        if recorder.runningAudioDisabled { return "Off" }
        if let names = recorder.runningAudioDeviceNames {
            if names.isEmpty { return "Off" }
            return names.count == 1 ? cleanAudioName(names[0]) : "\(names.count) sources"
        }
        let devices = recorder.lastHealth?.audioPipeline?.audioDevices ?? []
        if devices.isEmpty { return "Default audio" }
        return devices.count == 1 ? cleanAudioName(devices[0]) : "\(devices.count) sources"
    }

    private func cleanAudioName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " (input)", with: "")
            .replacingOccurrences(of: " (output)", with: "")
            .replacingOccurrences(of: "(input)", with: "")
            .replacingOccurrences(of: "(output)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var outputTargetDescription: String {
        switch settings.synthesisRuntime {
        case .ollama: return "Skill will be generated fully locally with Ollama (\(settings.ollamaModel))."
        case .claudeCode: return "Skill will be formatted for Claude Code (MCP)."
        case .codex: return "Skill will be generated through Codex with the recorder MCP."
        }
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.cardBackground.opacity(0.82))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.separator, lineWidth: 1))
    }
}

private struct FlowTeachingOrb: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 1.0 + 0.035 * sin(t * 1.8)
            let rotation = Angle.degrees(t * 18)

            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .clear,
                                    Color(flowHex: 0xFF8A3D).opacity(0.35),
                                    Color(flowHex: 0xB56BFF).opacity(0.42),
                                    .clear
                                ],
                                center: .center
                            ),
                            lineWidth: i == 0 ? 1.2 : 0.8
                        )
                        .scaleEffect(0.45 + CGFloat(i) * 0.16 + CGFloat(0.02 * sin(t + Double(i))))
                        .rotationEffect(rotation + .degrees(Double(i) * 28))
                        .opacity(0.8 - Double(i) * 0.12)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(flowHex: 0xFFB06A),
                                Color(flowHex: 0xE04F9E),
                                Color(flowHex: 0x2C103B)
                            ],
                            center: .init(x: 0.35 + 0.08 * sin(t * 0.9), y: 0.34),
                            startRadius: 4,
                            endRadius: 76
                        )
                    )
                    .frame(width: 112, height: 112)
                    .overlay(
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color(flowHex: 0xFF8A3D),
                                        Color(flowHex: 0xC16DFF),
                                        Color(flowHex: 0xFF8A3D)
                                    ],
                                    center: .center
                                ),
                                lineWidth: 1.4
                            )
                            .rotationEffect(rotation)
                    )
                    .shadow(color: Color(flowHex: 0xFF8A3D).opacity(0.34), radius: 28)
                    .shadow(color: Color(flowHex: 0xA970FF).opacity(0.24), radius: 38)
                    .scaleEffect(pulse)

                Circle()
                    .fill(Color(flowHex: 0xFF8A3D))
                    .frame(width: 24, height: 24)
                    .shadow(color: Color(flowHex: 0xFF8A3D).opacity(0.65), radius: 16)
            }
        }
    }
}

private struct FlowStarfield: View {
    var body: some View {
        Canvas { context, size in
            let dots: [(Double, Double, Double, UInt)] = [
                (0.08, 0.18, 1.0, 0xFF8A3D), (0.16, 0.36, 0.7, 0xA970FF),
                (0.28, 0.12, 1.4, 0xA970FF), (0.38, 0.64, 0.9, 0xFF8A3D),
                (0.52, 0.24, 0.8, 0xFFFFFF), (0.68, 0.18, 1.0, 0xA970FF),
                (0.76, 0.72, 0.7, 0xFFFFFF), (0.88, 0.30, 1.2, 0xFF8A3D),
                (0.94, 0.56, 0.8, 0xA970FF), (0.44, 0.84, 0.7, 0xFFFFFF)
            ]
            for dot in dots {
                let rect = CGRect(
                    x: size.width * dot.0,
                    y: size.height * dot.1,
                    width: dot.2,
                    height: dot.2
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color(flowHex: dot.3).opacity(0.8)))
            }
        }
        .background(
            RadialGradient(
                colors: [Color(flowHex: 0x172033).opacity(0.55), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
        )
    }
}

private struct ExtractionDetail: Identifiable {
    let id: String
    let icon: String
    let title: String
    let body: String
    let color: Color
    let explanation: String
    let examples: [String]

    static let steps = ExtractionDetail(
        id: "steps",
        icon: "list.bullet.rectangle.portrait.fill",
        title: "Steps",
        body: "Breakdown of the process",
        color: Color(flowHex: 0x9B5CFF),
        explanation: "Mengo turns the demonstration into an ordered procedure the skill can replay or adapt.",
        examples: ["Open the app or page", "Find the right record", "Make the requested change", "Verify the result"]
    )
    static let variables = ExtractionDetail(
        id: "variables",
        icon: "curlybraces",
        title: "Variables",
        body: "Dynamic values and inputs",
        color: Color(flowHex: 0x3DA8FF),
        explanation: "Values you mention as changeable become parameters instead of hard-coded one-off details.",
        examples: ["Customer name", "Date range", "File path", "Status or category"]
    )
    static let decisions = ExtractionDetail(
        id: "decisions",
        icon: "diamond.fill",
        title: "Decisions",
        body: "Choices and conditions",
        color: Color(flowHex: 0x39D98A),
        explanation: "Branches in your narration become rules the generated skill can follow next time.",
        examples: ["If the account is inactive", "When no result appears", "Use option A for urgent requests"]
    )
    static let apps = ExtractionDetail(
        id: "apps",
        icon: "macwindow",
        title: "Apps & Tools",
        body: "Applications and websites",
        color: Theme.accent,
        explanation: "Mengo records which apps, windows, and tools matter so the skill can target the right environment.",
        examples: ["Browser tab", "Terminal command", "Claude Code", "A local file or folder"]
    )
    static let actions = ExtractionDetail(
        id: "actions",
        icon: "arrow.triangle.2.circlepath",
        title: "Reusable Actions",
        body: "Repeatable interactions",
        color: Color(flowHex: 0x2F8CFF),
        explanation: "Repeated clicks, text entry, commands, and checks are summarized into reusable actions.",
        examples: ["Search", "Fill a form", "Run a command", "Export or save output"]
    )
}

private struct FlowExtractionDetailSheet: View {
    let detail: ExtractionDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: detail.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(detail.color)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 9).fill(detail.color.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail.title).font(Theme.headline).foregroundStyle(Theme.primaryText)
                    Text(detail.body).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }

            Text(detail.explanation)
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Examples").font(Theme.caption).foregroundStyle(Theme.primaryText)
                ForEach(detail.examples, id: \.self) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(detail.color)
                        Text(item).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.windowBackground)
    }
}

private struct FlowOutputTargetSheet: View {
    let settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Output Target").font(Theme.headline).foregroundStyle(Theme.primaryText)
                Text("Choose which local AI tool will turn demonstrations into skills.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            VStack(spacing: 8) {
                ForEach(SynthesisRuntime.allCases) { runtime in
                    runtimeRow(runtime)
                }
            }

            if settings.synthesisRuntime == .ollama {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ollama model").font(Theme.caption).foregroundStyle(Theme.secondaryText)
                    TextField("gpt-oss:20b", text: Binding(
                        get: { settings.ollamaModel },
                        set: { settings.ollamaModel = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("Use a tool-capable model (recommended: gpt-oss:20b). Install it first with: ollama pull \(settings.ollamaModel)")
                        .font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.windowBackground)
    }

    private func runtimeRow(_ runtime: SynthesisRuntime) -> some View {
        let selected = settings.synthesisRuntime == runtime
        return Button {
            settings.synthesisRuntime = runtime
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.mutedText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime.displayName)
                        .font(Theme.body)
                        .foregroundStyle(Theme.primaryText)
                    Text(runtimeNote(runtime))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.elevatedBackground : Theme.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent.opacity(0.6) : Theme.separator, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func runtimeNote(_ runtime: SynthesisRuntime) -> String {
        switch runtime {
        case .ollama: return "Runs locally through Codex OSS + Ollama; no cloud account or API key."
        case .claudeCode: return "Writes Claude Code skills into ~/.claude/skills."
        case .codex: return "Uses Codex with a pinned recorder MCP and local skill output."
        }
    }
}

private struct FlowGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Demonstration Guide").font(Theme.headline).foregroundStyle(Theme.primaryText)
            guideRow("Narrate decisions", "Say why you choose an option, not just what you click.")
            guideRow("Name variables", "Call out details that should change next time, like names, dates, paths, or accounts.")
            guideRow("Pause at important checks", "If you verify a result, say what you are checking for.")
            guideRow("Keep it natural", "Do the real task once. Mengo can clean up the structure afterward.")
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.windowBackground)
    }

    private func guideRow(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body).foregroundStyle(Theme.primaryText)
                Text(body).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension Color {
    init(flowHex: UInt) {
        self.init(
            .sRGB,
            red: Double((flowHex >> 16) & 0xFF) / 255.0,
            green: Double((flowHex >> 8) & 0xFF) / 255.0,
            blue: Double(flowHex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
