import SwiftUI

struct TimelineWindow: View {
    let state: AppState
    let controller: RecordingController

    @State private var items: [ScreenpipeClient.ThumbnailItem] = []
    @State private var lookbackMinutes: Int = 30
    @State private var selected: ScreenpipeClient.ThumbnailItem?
    @State private var loading: Bool = false
    @State private var loadError: String?

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick where the task started")
                .font(.headline)

            HStack {
                Text("Look back:")
                Picker("", selection: $lookbackMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
                .frame(width: 120)
                .labelsHidden()
                Button("Reload") { Task { await load() } }
                Spacer()
            }

            if loading {
                ProgressView().padding(.vertical, 30).frame(maxWidth: .infinity)
            } else if let err = loadError {
                Text("Failed to load timeline: \(err)")
                    .foregroundStyle(.red)
                    .padding(.vertical, 12)
            } else if items.isEmpty {
                Text("No screenpipe data in that range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            } else {
                List(items, id: \.timestamp, selection: $selected) { item in
                    HStack {
                        Text(formatter.string(from: item.timestamp))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        Text(item.appName).bold()
                        Text(item.windowName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .tag(item)
                    .contentShape(Rectangle())
                }
                .frame(minHeight: 300)
            }

            if let sel = selected {
                let now = Date()
                let secs = Int(now.timeIntervalSince(sel.timestamp))
                Text("Selected window: \(formatter.string(from: sel.timestamp)) → now (\(secs / 60)m \(secs % 60)s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { state.cancelBrowsingTimeline() }
                Button("Begin from here") {
                    if let sel = selected {
                        Task {
                            await controller.startRetroactive(bufferStart: sel.timestamp)
                            // Close this window by leaving browsingTimeline state.
                        }
                    }
                }
                .disabled(selected == nil)
                .keyboardShortcut(.return)
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 480)
        .task { await load() }
    }

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        let now = Date()
        let start = now.addingTimeInterval(-Double(lookbackMinutes) * 60)
        let client = controller.makeScreenpipeClient()
        do {
            let raw = try await client.thumbnailIndex(from: start, to: now, limit: 400)
            items = Self.decimate(raw, minIntervalSec: 15)
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            loadError = error.localizedDescription
        }
    }

    static func decimate(_ items: [ScreenpipeClient.ThumbnailItem],
                         minIntervalSec: TimeInterval) -> [ScreenpipeClient.ThumbnailItem] {
        var last: Date? = nil
        var out: [ScreenpipeClient.ThumbnailItem] = []
        for it in items.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let l = last, it.timestamp.timeIntervalSince(l) < minIntervalSec {
                continue
            }
            out.append(it)
            last = it.timestamp
        }
        return out
    }
}
