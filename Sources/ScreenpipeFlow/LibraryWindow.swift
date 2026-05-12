import SwiftUI

struct LibraryWindow: View {
    let state: AppState

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your flows").font(.title2)
            Divider()

            if state.library.isEmpty {
                VStack(spacing: 8) {
                    Text("No flows yet.").font(.headline)
                    Text("Record a demonstration to create your first one.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(state.library) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name).bold()
                            Text(dateFmt.string(from: entry.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.path])
                        }
                        Button("Review") {
                            state.reopenFlow(slug: entry.slug)
                        }
                        Button("Delete") {
                            try? FileManager.default.removeItem(at: entry.path)
                            state.removeFlow(slug: entry.slug)
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 400)
    }
}
