import SwiftUI

/// Right-rail live feed. Header + the most recent ~12 typed events + a
/// "View All Activity" footer link. The store's `task()` keeps the list
/// fresh (5-s poll diff against the recorder DB).
struct ActivityFeedView: View {
    let store: MemoryDashboardStore
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            list
            Divider().overlay(Theme.separator)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Text("Recent Activity").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Theme.recording).frame(width: 7, height: 7)
                    .opacity(pulseDot ? 1 : 0.45)
                Text("Live").font(Theme.caption).foregroundStyle(Theme.recording)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .onAppear { pulseDot.toggle() }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseDot)
    }

    @State private var pulseDot = false

    @ViewBuilder private var list: some View {
        if store.recentActivity.isEmpty {
            VStack(spacing: 6) {
                Text("Nothing yet").font(Theme.body).foregroundStyle(Theme.secondaryText)
                Text("New activity will appear here as Mengo watches your work.")
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.horizontal, 16)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.recentActivity.prefix(12)) { event in
                        ActivityRow(event: event)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        Divider().overlay(Theme.separator).padding(.horizontal, 16)
                    }
                }
            }
            .frame(maxHeight: 540)
        }
    }

    @ViewBuilder private var footer: some View {
        Button(action: onViewAll) {
            HStack {
                Text("View All Activity").font(Theme.body).foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.mutedText)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(timeAgo).font(Theme.caption).foregroundStyle(Theme.mutedText)
                if let s = subtitle {
                    Text(s).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var iconAvatar: some View {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Theme.elevatedBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
            )
    }

    private var icon: String {
        switch event {
        case .screenshot:    return "camera"
        case .transcription: return "waveform"
        case .urlVisited:    return "globe"
        }
    }

    private var title: String {
        switch event {
        case .screenshot:    return "Screenshot Captured"
        case .transcription: return "Transcription Added"
        case .urlVisited:    return "Page Visited"
        }
    }

    private var subtitle: String? {
        switch event {
        case .screenshot(_, _, let app, let win):
            return win.flatMap { $0.isEmpty ? nil : $0 } ?? app
        case .transcription(_, _, let snippet):
            return "\u{201C}\(snippet)\u{201D}"
        case .urlVisited(_, _, let url, _):
            return URL(string: url)?.host ?? url
        }
    }

    private var timeAgo: String {
        let delta = Date().timeIntervalSince(event.timestamp)
        if delta < 60 { return "just now" }
        if delta < 3600 {
            let mins = Int(delta / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s") ago"
        }
        if delta < 86_400 {
            let hours = Int(delta / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        let days = Int(delta / 86_400)
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}
