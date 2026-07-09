import SwiftUI

/// Lists the flows Mengo has created (from `FlowController.library`). Adapted
/// from V1's `LibraryWindow` — now an inline pane. "Re-open in Review" jumps to
/// the Flow tab in its reviewing state.
struct LibraryPane: View {
    let flow: FlowController
    let onOpenReview: () -> Void
    @State private var pendingDelete: FlowEntry?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Library").font(Theme.title).foregroundStyle(Theme.primaryText)
                if flow.library.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(Theme.mutedText)
                        Text("No flows yet").font(Theme.headline).foregroundStyle(Theme.primaryText)
                        Text("Record one from the Flow tab.").font(Theme.body).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(flow.library.enumerated()), id: \.element.id) { idx, entry in
                            row(entry)
                            if idx < flow.library.count - 1 { Divider().overlay(Theme.separator) }
                        }
                    }
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .alert("Delete this flow?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { if let e = pendingDelete { flow.deleteFlow(slug: e.slug) }; pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes \(pendingDelete?.name ?? "") from ~/.claude/skills/. It can't be undone.")
        }
    }

    private func row(_ entry: FlowEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(Theme.body.weight(.medium)).foregroundStyle(entry.exists ? Theme.primaryText : Theme.mutedText)
                    .lineLimit(1).truncationMode(.middle)
                Text(entry.exists ? Self.dateFmt.string(from: entry.createdAt) : "missing — removed outside Mengo")
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
            }
            Spacer(minLength: 8)
            // Compact icon actions (with tooltips) — keeps rows narrow so the window stays freely resizable.
            if entry.exists {
                Button {
                    flow.reopenInReview(slug: entry.slug)
                    onOpenReview()
                } label: { Image(systemName: "square.and.pencil") }
                    .help("Re-open in Review").buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button { NSWorkspace.shared.activateFileViewerSelecting([entry.path]) } label: { Image(systemName: "folder") }
                    .help("Open in Finder").buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button { pendingDelete = entry } label: { Image(systemName: "trash") }
                    .help("Delete").buttonStyle(.plain).foregroundStyle(Theme.mutedText)
            } else {
                Button { flow.deleteFlow(slug: entry.slug) } label: { Image(systemName: "minus.circle") }
                    .help("Remove from list").buttonStyle(.plain).foregroundStyle(Theme.mutedText)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
    }
}
