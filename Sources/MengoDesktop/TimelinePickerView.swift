import SwiftUI

/// The `.browsingTimeline` UI — "pick where the task started" over the recorder's
/// recent buffer (a moment list, not thumbnails). Adapted from V1's `TimelineWindow`.
struct TimelinePickerView: View {
    let flow: FlowController

    @State private var lookbackMinutes = 30
    @State private var moments: [Moment] = []
    @State private var selected: Moment?
    @State private var loading = false
    @State private var loadError: String?

    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm:ss a"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grab last N minutes").font(Theme.title).foregroundStyle(Theme.primaryText)
                Text("Pick the moment your task started. Mengo records forward from now — and the synthesizer reconstructs the part before this point from screen + accessibility (those steps come back flagged for you to verify).")
                    .font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text("Look back:").font(Theme.body).foregroundStyle(Theme.secondaryText)
                Picker("", selection: $lookbackMinutes) {
                    Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120)
                }
                .labelsHidden().frame(width: 110)
                .onChange(of: lookbackMinutes) { _, _ in Task { await reload() } }
                Button("Reload") { Task { await reload() } }.buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            list
            if let sel = selected {
                let secs = max(0, Int(Date().timeIntervalSince(sel.timestamp)))
                Text("Selected: \(Self.timeFmt.string(from: sel.timestamp)) → now  (\(secs / 60)m \(secs % 60)s)")
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { flow.cancelBrowsingTimeline() }.buttonStyle(.bordered)
                Button("Begin from here") { if let m = selected { Task { await flow.startRetroactive(bufferStart: m.timestamp) } } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(selected == nil).keyboardShortcut(.return)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .task { await reload() }
    }

    @ViewBuilder private var list: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let e = loadError {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.paused)
                Text(e).font(Theme.body).foregroundStyle(Theme.secondaryText)
            }.frame(maxWidth: .infinity, minHeight: 200)
        } else if moments.isEmpty {
            Text("No Mengo Memory data in that range. Try a longer look-back.")
                .font(Theme.body).foregroundStyle(Theme.mutedText).frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(moments.reversed().enumerated()), id: \.element.id) { idx, m in
                        row(m)
                        if idx < moments.count - 1 { Divider().overlay(Theme.separator) }
                    }
                }
            }
            .frame(minHeight: 240, maxHeight: 360)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        }
    }

    private func row(_ m: Moment) -> some View {
        let isSel = selected == m
        return HStack(spacing: 12) {
            Text(Self.timeFmt.string(from: m.timestamp)).font(.system(.body, design: .monospaced))
                .foregroundStyle(isSel ? Color.white : Theme.secondaryText).frame(width: 110, alignment: .leading)
            Text(m.appName.isEmpty ? "—" : m.appName).font(Theme.body.weight(.medium)).foregroundStyle(isSel ? Color.white : Theme.primaryText)
            Text(m.windowName).font(Theme.body).foregroundStyle(isSel ? Color.white.opacity(0.85) : Theme.mutedText).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSel ? Theme.accent : Color.clear)
        .onTapGesture { selected = m }
    }

    private func reload() async {
        loading = true; loadError = nil; selected = nil
        do { moments = try await flow.loadMoments(lookbackMinutes: lookbackMinutes) }
        catch { loadError = error.localizedDescription }
        loading = false
    }
}
