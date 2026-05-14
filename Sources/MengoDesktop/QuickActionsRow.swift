import SwiftUI

/// Five tiles below the Sessions / Top Apps row. Routes are external —
/// the dashboard pane supplies callbacks so this view stays free of
/// AppState / FlowController / NSWorkspace coupling.
struct QuickActionsRow: View {
    var onConfigureSources: () -> Void
    var onCreateFlow: () -> Void
    var onTrainSkill: () -> Void
    var onOpenStudio: () -> Void
    var onImportWorkflow: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            tile(systemImage: "display.2", title: "Configure Sources",
                 caption: "Monitors, audio & apps", action: onConfigureSources)
            tile(systemImage: "wand.and.stars", title: "Create Flow",
                 caption: "Build automation",        action: onCreateFlow)
            tile(systemImage: "sparkles",   title: "Train New Skill",
                 caption: "Teach Mengo a skill",     action: onTrainSkill)
            tile(systemImage: "rectangle.connected.to.line.below", title: "Open Studio",
                 caption: "Edit your skills",        action: onOpenStudio)
            tile(systemImage: "square.and.arrow.down", title: "Import Workflow",
                 caption: "Bring in existing flow",  action: onImportWorkflow)
        }
    }

    private func tile(systemImage: String, title: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.body).foregroundStyle(Theme.primaryText).lineLimit(1)
                    Text(caption).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Theme.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.separator, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}
