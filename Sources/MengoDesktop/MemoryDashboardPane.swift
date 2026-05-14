import SwiftUI

/// The Memory Dashboard — full rewrite of the old `MemoryPane`. Two-column
/// layout: a center column (hero + middle cards + quick actions) and a
/// right rail (live activity feed). When the window is narrower than the
/// `narrowBreakpoint`, the rail collapses below the center column.
///
/// Part B lands the hero + right rail; the four middle cards are
/// placeholders until Parts C and D fill them in.
struct MemoryDashboardPane: View {
    let recorder: RecorderController
    let account: AccountStore
    let settings: SettingsStore
    let store: MemoryDashboardStore

    @State private var showAdvancedSources = false
    @State private var showScheduleStub = false

    private let narrowBreakpoint: CGFloat = 1100

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                let useRail = geo.size.width >= narrowBreakpoint
                let body = VStack(alignment: .leading, spacing: 22) {
                    MemoryHero(
                        recorder: recorder,
                        settings: settings,
                        onSchedule: { showScheduleStub = true },
                        onShowAdvancedSources: { showAdvancedSources = true },
                        onShowSettings: { /* C3 will route to .settings */ }
                    )
                    InsightsCarouselPlaceholder()
                    HStack(alignment: .top, spacing: 22) {
                        RecentSessionsPlaceholder().frame(maxWidth: .infinity)
                        TopApplicationsPlaceholder().frame(maxWidth: .infinity)
                    }
                    QuickActionsRowPlaceholder()
                    if !useRail {
                        ActivityFeedView(store: store)   // tucks below the middle column
                    }
                }

                HStack(alignment: .top, spacing: 22) {
                    body
                    if useRail {
                        ActivityFeedView(store: store).frame(width: 300)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground],
                           startPoint: .top, endPoint: .bottom)
        )
        .sheet(isPresented: $showAdvancedSources) {
            RecordingSourcesView(recorder: recorder)
        }
        .alert("Schedule Recording", isPresented: $showScheduleStub) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Recurring + one-off schedules land in Part D.")
        }
        .task {
            await store.task()
        }
    }
}

// MARK: - Placeholders (replaced in Parts C + D)

private struct InsightsCarouselPlaceholder: View {
    var body: some View {
        PlaceholderCard(
            title: "Mengo Insights",
            caption: "Personalized insights from your digital world.",
            hint: "Insights land in Part D — heuristic candidates plus an opt-in LLM polish pass."
        )
    }
}

private struct RecentSessionsPlaceholder: View {
    var body: some View {
        PlaceholderCard(
            title: "Recent Sessions",
            caption: "Recent focused-work blocks across your apps.",
            hint: "Sessions land in Part C — clustered from the recorder DB."
        )
    }
}

private struct TopApplicationsPlaceholder: View {
    var body: some View {
        PlaceholderCard(
            title: "Top Applications",
            caption: "Where your time goes.",
            hint: "Top Apps lands in Part C — bar chart over today / 7d / 30d."
        )
    }
}

private struct QuickActionsRowPlaceholder: View {
    var body: some View {
        PlaceholderCard(
            title: "Quick Actions",
            caption: "Configure Sources · Create Flow · Train Skill · Open Studio · Import Workflow",
            hint: "Quick Actions land in Part C — five tiles routing to existing destinations."
        )
    }
}

private struct PlaceholderCard: View {
    let title: String
    let caption: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text(caption).font(Theme.body).foregroundStyle(Theme.secondaryText)
            Text(hint).font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.separator, lineWidth: 1))
        )
    }
}
