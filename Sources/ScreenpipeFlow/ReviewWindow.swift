import SwiftUI

struct ReviewWindow: View {
    let state: AppState
    let controller: RecordingController
    let skillDir: URL

    @State private var skillMarkdown: String = ""
    @State private var loadError: String?
    @State private var feedbackText: String = ""
    @State private var showingRegenerateField: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: rendered SKILL.md (raw markdown for V1)
            VStack(alignment: .leading, spacing: 4) {
                Text(skillDir.lastPathComponent)
                    .font(.title2)
                Divider()
                if let err = loadError {
                    Text("Failed to load SKILL.md: \(err)")
                        .foregroundStyle(.red)
                } else {
                    ScrollView {
                        Text(skillMarkdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .border(.tertiary)
                }
            }
            .frame(minWidth: 400)

            // Right: actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions").font(.headline)

                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([skillDir])
                }

                Button("Save and close") {
                    state.finalize()
                    closeReviewWindow()
                }
                .keyboardShortcut(.return)

                Divider()

                if showingRegenerateField {
                    Text("Tell the synthesizer what to fix:")
                    TextEditor(text: $feedbackText)
                        .frame(height: 80)
                        .border(.tertiary)
                    HStack {
                        Button("Regenerate") {
                            guard let session = state.lastSession else {
                                loadError = "lastSession is nil — can't regenerate. Try Mode A again."
                                return
                            }
                            let feedback = feedbackText
                            Task { @MainActor in
                                await controller.regenerate(
                                    previousSkillPath: skillDir,
                                    userFeedback: feedback,
                                    originalSession: session)
                            }
                            showingRegenerateField = false
                            feedbackText = ""
                        }
                        Button("Cancel") {
                            showingRegenerateField = false
                            feedbackText = ""
                        }
                    }
                } else {
                    Button("Regenerate with feedback…") {
                        showingRegenerateField = true
                    }
                }

                Divider()

                Button("Discard skill") {
                    try? FileManager.default.removeItem(at: skillDir)
                    state.removeFlow(slug: skillDir.lastPathComponent)
                    state.finalize()
                    closeReviewWindow()
                }
                .tint(.red)

                Spacer()
            }
            .frame(minWidth: 220)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
        .task { loadSkill() }
    }

    private func loadSkill() {
        let md = skillDir.appendingPathComponent("SKILL.md")
        do {
            skillMarkdown = try String(contentsOf: md, encoding: .utf8)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func closeReviewWindow() {
        NSApplication.shared.windows.first { $0.title == "Review" }?.close()
    }
}
