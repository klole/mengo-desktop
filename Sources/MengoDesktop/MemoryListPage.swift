import SwiftUI

/// Shared "View All …" sheet. Three kinds, one container, one set of styles —
/// activity / sessions / applications all read from the dashboard store's
/// existing in-memory collections (no extra DB queries).
struct MemoryListPage: View {
    enum Kind: String, Identifiable {
        case activity
        case sessions
        case applications
        var id: String { rawValue }

        var title: String {
            switch self {
            case .activity:     return "All Activity"
            case .sessions:     return "All Sessions"
            case .applications: return "All Applications"
            }
        }
    }

    let kind: Kind
    let store: MemoryDashboardStore
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            ScrollView { content.padding(20) }
        }
        .background(Theme.paneBackground)
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text(kind.title).font(Theme.title).foregroundStyle(Theme.primaryText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Theme.cardBackground)
                            .overlay(Circle().stroke(Theme.separator, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .activity:     activityList
        case .sessions:     sessionsList
        case .applications: applicationsList
        }
    }

    @ViewBuilder private var activityList: some View {
        if store.recentActivity.isEmpty {
            emptyState(message: "No activity yet")
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(store.recentActivity) { event in
                    activityRow(event)
                }
            }
        }
    }

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activityIcon(event)).font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Theme.elevatedBackground)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle(event)).font(Theme.body).foregroundStyle(Theme.primaryText)
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
                if let s = activitySubtitle(event) {
                    Text(s).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var sessionsList: some View {
        if store.recentSessions.isEmpty {
            emptyState(message: "No sessions yet")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(store.recentSessions) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ s: SessionRow) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: -8) {
                ForEach(Array(s.appIcons.prefix(3).enumerated()), id: \.offset) { _, icon in
                    Image(systemName: icon).font(.system(size: 14))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Theme.elevatedBackground)
                                .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
                        )
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(Theme.body).foregroundStyle(Theme.primaryText)
                Text("\(s.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(formattedDuration(s.duration)) · \(s.frameCount) frames")
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                if let sub = s.subtitle, !sub.isEmpty {
                    Text(sub).font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var applicationsList: some View {
        if store.topApps.isEmpty {
            emptyState(message: "No app data yet")
        } else {
            VStack(spacing: 10) {
                ForEach(store.topApps) { row in
                    HStack(spacing: 14) {
                        Image(systemName: row.iconName).font(.system(size: 16))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10).fill(Theme.elevatedBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName).font(Theme.body).foregroundStyle(Theme.primaryText)
                            Text("\(row.frameCount) frames · \(row.sharePercent)% of \(store.topAppsWindow.displayName.lowercased())")
                                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
                    )
                }
            }
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 8) {
            Text(message).font(Theme.body).foregroundStyle(Theme.secondaryText)
            Text("Check back once Mengo has been watching for a bit.")
                .font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Helpers

    private func activityIcon(_ e: ActivityEvent) -> String {
        switch e {
        case .screenshot: return "camera"
        case .transcription: return "waveform"
        case .urlVisited: return "globe"
        }
    }

    private func activityTitle(_ e: ActivityEvent) -> String {
        switch e {
        case .screenshot: return "Screenshot Captured"
        case .transcription: return "Transcription Added"
        case .urlVisited: return "Page Visited"
        }
    }

    private func activitySubtitle(_ e: ActivityEvent) -> String? {
        switch e {
        case .screenshot(_, _, let app, let win):
            return win.flatMap { $0.isEmpty ? nil : $0 } ?? app
        case .transcription(_, _, let snippet):
            return "\u{201C}\(snippet)\u{201D}"
        case .urlVisited(_, _, let url, _):
            return URL(string: url)?.host ?? url
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let mins  = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
