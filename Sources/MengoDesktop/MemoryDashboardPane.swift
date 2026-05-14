import SwiftUI
import AppKit

/// The Memory Dashboard — full rewrite of the old `MemoryPane`. Two-column
/// layout: a center column (hero + middle cards + quick actions) and a
/// right rail (live activity feed). When the window is narrower than the
/// `narrowBreakpoint`, the rail collapses below the center column.
///
/// Part B lands the hero + right rail; the four middle cards are
/// placeholders until Parts C and D fill them in.
struct MemoryDashboardPane: View {
    let appState: AppState
    let recorder: RecorderController
    let account: AccountStore
    let settings: SettingsStore
    let store: MemoryDashboardStore

    @State private var showAdvancedSources = false
    @State private var showScheduleStub = false
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
                        onSchedule: { showScheduleStub = true },
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
                        onOpenStudio:       { openStudio() },
                        onImportWorkflow:   { importWorkflow() }
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
        .alert("Schedule Recording", isPresented: $showScheduleStub) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Recurring + one-off schedules land in Part D.")
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
            // Time-range filter on MemoryListPage is a follow-up; for v1 the
            // CTA opens the full activity list and the user can scroll.
            listSheet = .activity
        case .seeDetails:
            listSheet = .activity
        }
    }

    // MARK: - Quick Actions routes

    private func openStudio() {
        if account.isPro {
            appState.selectedSection = .studio
        } else {
            Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) }
        }
    }

    private func importWorkflow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import workflow"
        if panel.runModal() == .OK, let url = panel.url {
            Log.line("Import workflow: \(url.path) — full import lands in the Studio phase.")
        }
    }
}

