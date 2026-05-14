import SwiftUI

/// Horizontal-scrolling carousel of Mengo Insights. Each card shows the
/// insight's kind icon + headline, the engine-generated title + body, and
/// a primary CTA button. CTAs are routed by `onInvoke` — the dashboard pane
/// owns navigation.
struct InsightsCarousel: View {
    let insights: [Insight]
    var onInvoke: (InsightCTA) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if insights.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight, onCTA: { onInvoke(insight.cta) })
                                .frame(width: 260)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Mengo Insights").font(Theme.title).foregroundStyle(Theme.primaryText)
            badge
            Spacer()
        }
    }

    @ViewBuilder private var badge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
            Text("AI").font(Theme.caption).fontWeight(.semibold)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            Capsule().fill(Theme.accent.opacity(0.15))
                .overlay(Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
        )
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mengo will surface patterns here.")
                .font(Theme.body).foregroundStyle(Theme.primaryText)
            Text("As your recorder captures activity, you'll see repeated workflows, automation opportunities, and focus blocks worth turning into flows or skills.")
                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.separator, lineWidth: 1))
        )
    }
}

private struct InsightCard: View {
    let insight: Insight
    var onCTA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: insight.kind.symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(insight.kind.headline).font(Theme.caption).fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }
            Text(insight.body).font(Theme.body).foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            Spacer(minLength: 6)
            Button(action: onCTA) {
                HStack(spacing: 6) {
                    Text(insight.cta.label).font(Theme.body)
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Theme.elevatedBackground)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.separator, lineWidth: 1))
        )
    }
}
