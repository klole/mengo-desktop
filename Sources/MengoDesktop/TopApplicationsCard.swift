import SwiftUI

/// "Top Applications" card — horizontal bar list of where the user's frames
/// land, with a Today / 7d / 30d window picker. Pulls from
/// `store.topApps`; the picker drives `store.setTopAppsWindow`.
struct TopApplicationsCard: View {
    let store: MemoryDashboardStore
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            content
            Divider().overlay(Theme.separator)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text("Top Applications").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Spacer()
            windowPicker
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    @ViewBuilder private var windowPicker: some View {
        Menu {
            ForEach(TopAppsWindow.allCases, id: \.self) { w in
                Button {
                    Task { await store.setTopAppsWindow(w) }
                } label: {
                    if store.topAppsWindow == w {
                        Label(w.displayName, systemImage: "checkmark")
                    } else {
                        Text(w.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.topAppsWindow.displayName).font(Theme.body)
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(Theme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Theme.elevatedBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var content: some View {
        if store.topApps.isEmpty {
            VStack(spacing: 6) {
                Text("No data yet").font(Theme.body).foregroundStyle(Theme.secondaryText)
                Text("Mengo will fill this in as your recorder captures activity.")
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(.horizontal, 18)
        } else {
            VStack(spacing: 10) {
                ForEach(store.topApps) { row in
                    BarRow(row: row)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }

    @ViewBuilder private var footer: some View {
        Button(action: onViewAll) {
            HStack {
                Text("View All Applications").font(Theme.body).foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.mutedText)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BarRow: View {
    let row: AppUsageRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22)
            Text(row.displayName).font(Theme.body).foregroundStyle(Theme.primaryText)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.elevatedBackground).frame(height: 6)
                    Capsule().fill(Theme.accent).frame(width: barWidth(in: geo.size.width), height: 6)
                }
            }
            .frame(height: 6)
            Text("\(row.sharePercent)%").font(Theme.caption).foregroundStyle(Theme.secondaryText)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        max(2, width * CGFloat(row.sharePercent) / 100)
    }
}
