import SwiftUI

/// The Flow pane's `reviewing` state — shows the just-synthesized skill (rendered
/// SKILL.md, editable name/description/parameters, read-only step list) with
/// Save / Regenerate-with-feedback / Discard. Adapted from V1's `ReviewWindow`.
struct SkillReviewView: View {
    let flow: FlowController
    let skillDir: URL

    @State private var name: String = ""
    @State private var skillDescription: String = ""
    @State private var bodyMarkdown: String = ""
    @State private var parameters: [FlowParameter] = []
    @State private var steps: [String] = []
    @State private var loadError: String?
    @State private var feedback: String = ""
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let e = loadError {
                        Label("Couldn't load the skill files: \(e)", systemImage: "exclamationmark.triangle")
                            .font(Theme.body).foregroundStyle(Theme.paused)
                    }
                    markdownSection
                    parametersSection
                    stepsSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .task { load() }
    }

    // MARK: header (editable name + description)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Skill name", text: $name).textFieldStyle(.plain)
                .font(Theme.title).foregroundStyle(Theme.primaryText)
            TextField("Short description (when should Claude use this skill?)", text: $skillDescription, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...3)
                .font(Theme.body).foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    // MARK: SKILL.md preview

    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SKILL.md").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text(rendered(bodyMarkdown)).font(Theme.body).foregroundStyle(Theme.secondaryText)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        }
    }

    private func rendered(_ md: String) -> AttributedString {
        (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(md)
    }

    // MARK: parameters

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parameters").font(Theme.headline).foregroundStyle(Theme.primaryText)
            if parameters.isEmpty {
                Text("No parameters — this skill runs the same way every time.")
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
            }
            ForEach(Array(parameters.enumerated()), id: \.element.id) { idx, _ in
                HStack(spacing: 10) {
                    TextField("name", text: Binding(get: { parameters[idx].name }, set: { parameters[idx].name = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                    TextField("default value", text: Binding(get: { parameters[idx].defaultValue ?? "" }, set: { parameters[idx].defaultValue = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder)
                    if parameters[idx].autoDetected {
                        Text("auto-detected").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.paused)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(Theme.cardBackground, in: Capsule())
                    }
                    Button { parameters.remove(at: idx) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(Theme.mutedText)
                }
            }
            Button { parameters.append(FlowParameter(name: "new_parameter", description: nil, defaultValue: nil, autoDetected: false)) } label: {
                Label("Add parameter", systemImage: "plus")
            }.buttonStyle(.plain).foregroundStyle(Theme.accent).font(Theme.caption)
        }
    }

    // MARK: steps (read-only)

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Steps").font(Theme.headline).foregroundStyle(Theme.primaryText)
            if steps.isEmpty {
                Text("(No structured steps — see SKILL.md above.)").font(Theme.caption).foregroundStyle(Theme.mutedText)
            }
            ForEach(steps, id: \.self) { Text($0).font(Theme.body).foregroundStyle(Theme.secondaryText) }
            if !steps.isEmpty {
                Text("Steps are read-only here. To change one, use “Regenerate with feedback…” below — the visual step editor is coming in Studio.")
                    .font(Theme.caption).foregroundStyle(Theme.mutedText)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showFeedback {
                Text("Tell the synthesizer what to change:").font(Theme.caption).foregroundStyle(Theme.secondaryText)
                TextEditor(text: $feedback).frame(height: 64).font(Theme.body)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                HStack {
                    Button("Regenerate") { let f = feedback; showFeedback = false; feedback = ""; Task { await flow.regenerate(feedback: f) } }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { showFeedback = false; feedback = "" }.buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    Button("Regenerate with feedback…") { showFeedback = true }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Button("Open in Finder") { NSWorkspace.shared.activateFileViewerSelecting([skillDir]) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Spacer(minLength: 12)
                    Button("Discard") { flow.discard() }.buttonStyle(.bordered).tint(Theme.stopped)
                    Button("Save") { flow.save(name: name, description: skillDescription.isEmpty ? nil : skillDescription, parameters: parameters) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.return)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    // MARK: load

    private func load() {
        let md = (try? String(contentsOf: skillDir.appendingPathComponent("SKILL.md"), encoding: .utf8))
        let flowData = try? Data(contentsOf: skillDir.appendingPathComponent("flow.json"))
        if let md {
            let parsed = SkillFiles.parseSkillMarkdown(md)
            name = parsed.name ?? skillDir.lastPathComponent
            skillDescription = parsed.description ?? ""
            bodyMarkdown = parsed.body
        } else {
            name = skillDir.lastPathComponent
            loadError = "SKILL.md not found at \(skillDir.path)"
        }
        if let flowData {
            parameters = SkillFiles.parseFlowParameters(flowData)
            steps = SkillFiles.parseFlowStepSummaries(flowData)
        }
    }
}
