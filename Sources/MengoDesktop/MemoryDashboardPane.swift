import SwiftUI

/// The Memory Dashboard — full rewrite of the old `MemoryPane`. Two-column
/// layout: a center column (hero + middle cards + quick actions) and a
/// right rail (live activity feed). When the window is narrower than the
/// `narrowBreakpoint`, the rail collapses below the center column.
///
struct MemoryDashboardPane: View {
    let appState: AppState
    let recorder: RecorderController
    let settings: SettingsStore
    let store: MemoryDashboardStore

    @State private var showAdvancedSources = false
    @State private var showSchedule = false
    @State private var listSheet: MemoryListPage.Kind?

    private let narrowBreakpoint: CGFloat = 1100

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                let useRail = geo.size.width >= narrowBreakpoint
                let body = VStack(alignment: .leading, spacing: 22) {
                    MemoryHero(
                        recorder: recorder,
                        settings: settings,
                        onSchedule: { showSchedule = true },
                        onShowAdvancedSources: { showAdvancedSources = true },
                        onShowSettings: { appState.selectedSection = .settings }
                    )
                    InsightsCarousel(insights: store.insights, onInvoke: invokeInsightCTA)
                    HStack(alignment: .top, spacing: 22) {
                        RecentSessionsCard(store: store, onViewAll: { listSheet = .sessions })
                            .frame(maxWidth: .infinity)
                        TopApplicationsCard(store: store, onViewAll: { listSheet = .applications })
                            .frame(maxWidth: .infinity)
                    }
                    QuickActionsRow(
                        onConfigureSources: { showAdvancedSources = true },
                        onCreateFlow:       { appState.selectedSection = .flow },
                        onTrainSkill:       { appState.selectedSection = .flow },
                        onOpenStudio:       { openStudio() }
                    )
                    if !useRail {
                        ActivityFeedView(store: store, onViewAll: { listSheet = .activity })
                    }
                }

                HStack(alignment: .top, spacing: 22) {
                    body
                    if useRail {
                        ActivityFeedView(store: store, onViewAll: { listSheet = .activity })
                            .frame(width: 300)
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
        .sheet(item: $listSheet) { kind in
            MemoryListPage(kind: kind, store: store, onClose: { listSheet = nil })
        }
        .sheet(isPresented: $showSchedule) {
            ScheduleRecordingSheet(settings: settings, onClose: { showSchedule = false })
        }
        .task {
            await store.task()
        }
    }

    // MARK: - Insight CTA routes

    private func invokeInsightCTA(_ cta: InsightCTA) {
        switch cta {
        case .createSkill, .createFlow:
            appState.selectedSection = .flow
        case .viewMemory:
            listSheet = .activity
        case .seeDetails:
            listSheet = .activity
        }
    }

    // MARK: - Quick Actions routes

    private func openStudio() {
        appState.selectedSection = .studio
    }
}
