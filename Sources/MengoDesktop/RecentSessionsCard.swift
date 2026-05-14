import SwiftUI

/// "Recent Sessions" card — three rows of `SessionRow` from the dashboard
/// store, each with an icon stack (top 3 apps), title + subtitle, duration +
/// frame count, and an Open Session button. The store populates from
/// `MemoryDB.recentFrames` + `SessionsService.cluster`; this view is purely
/// display.
struct RecentSessionsCard: View {
    let store: MemoryDashboardStore
    var onViewAll: () -> Void = {}
    var onOpenSession: (SessionRow) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text("Recent Sessions").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Spacer()
            Button(action: onViewAll) {
                HStack(spacing: 4) {
                    Text("View All Sessions").font(Theme.body)
                    Image(systemName: "arrow.right").font(.system(size: 11))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    @ViewBuilder private var content: some View {
        let sessions = store.recentSessions.prefix(3)
        if sessions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                    SessionRowView(session: session, onOpen: { onOpenSession(session) })
                        .padding(.horizontal, 18).padding(.vertical, 12)
                    if idx < sessions.count - 1 {
                        Divider().overlay(Theme.separator).padding(.horizontal, 18)
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No sessions yet").font(Theme.body).foregroundStyle(Theme.secondaryText)
            Text("Sessions are private and stored only on this device.")
                .font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.horizontal, 18)
    }
}

private struct SessionRowView: View {
    let session: SessionRow
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            iconStack
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(Theme.body).foregroundStyle(Theme.primaryText).lineLimit(1)
                if let subtitle = session.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            stats
            Button(action: onOpen) {
                Text("Open Session").font(Theme.body)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .foregroundStyle(Theme.primaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Theme.elevatedBackground)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var iconStack: some View {
        let icons = session.appIcons.prefix(3)
        HStack(spacing: -8) {
            ForEach(Array(icons.enumerated()), id: \.offset) { _, name in
                Image(systemName: name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Theme.elevatedBackground)
                            .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
                    )
            }
        }
        .frame(minWidth: 60, alignment: .leading)
    }

    @ViewBuilder private var stats: some View {
        HStack(spacing: 14) {
            statBlock(systemImage: "clock", value: formattedDuration(session.duration))
            statBlock(systemImage: "photo", value: "\(session.frameCount)")
        }
    }

    private func statBlock(systemImage: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(Theme.mutedText)
            Text(value).font(Theme.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let mins  = (total % 3600) / 60
        let secs  = total % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        if mins  > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }
}
