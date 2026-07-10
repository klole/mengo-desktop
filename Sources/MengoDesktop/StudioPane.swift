import SwiftUI
import AppKit

/// Mengo Studio: a visual editor for saved flows. Phase 5A is a vertical step
/// editor backed by `FlowDocument` / `StudioController`.
struct StudioPane: View {
    let flow: FlowController
    @Bindable var studio: StudioController

    @State private var pendingSwitchTo: FlowEntry?
    @State private var pendingClose: Bool = false
    @State private var viewMode: EditorViewMode = .timeline
    @State private var showingNLEditor: Bool = false
    @State private var nlEditorInstruction: String = ""

    enum EditorViewMode: String, CaseIterable, Identifiable {
        case timeline, canvas
        var id: String { rawValue }
        var label: String { self == .timeline ? "Timeline" : "Canvas" }
        var icon: String { self == .timeline ? "list.bullet" : "point.3.connected.trianglepath.dotted" }
    }

    /// True only when the user can make in-memory edits right now — no async
    /// runtime action may be in flight. Async actions reload `flow.json` on
    /// success, so allowing concurrent in-memory edits would silently lose
    /// them. Pass this through as `editable:` to all subviews.
    private var isEditingEnabled: Bool { !studio.isAsyncRunning }
    private var savedFlows: [FlowEntry] { flow.library.filter(\.exists) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 260)
            Divider().overlay(Theme.separator)
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .task {
            studio.reconcile(library: savedFlows)
            drainPendingOpen()
        }
        .onChange(of: flow.library) { _, _ in studio.reconcile(library: savedFlows) }
        .onChange(of: studio.pendingOpen?.slug) { _, _ in drainPendingOpen() }
        .alert("Discard unsaved changes?",
               isPresented: Binding(get: { pendingSwitchTo != nil || pendingClose },
                                     set: { if !$0 { pendingSwitchTo = nil; pendingClose = false } })) {
            Button("Discard", role: .destructive) {
                if let target = pendingSwitchTo { studio.open(target) }
                else if pendingClose { studio.close() }
                pendingSwitchTo = nil; pendingClose = false
            }
            Button("Keep editing", role: .cancel) {
                pendingSwitchTo = nil; pendingClose = false
            }
        } message: {
            Text("You have unsaved edits in this flow. Switching will discard them.")
        }
    }

    // MARK: - Sidebar (flow picker)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Flows").font(Theme.headline).foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(savedFlows.count)").font(Theme.caption).foregroundStyle(Theme.mutedText)
            }
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)

            if savedFlows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Theme.mutedText)
                    Text("No flows yet").font(Theme.body).foregroundStyle(Theme.secondaryText)
                    Text("Record one from the Flow tab.").font(Theme.caption).foregroundStyle(Theme.mutedText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 28).padding(.horizontal, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(savedFlows) { entry in
                            sidebarRow(entry)
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.windowBackground)
    }

    private func sidebarRow(_ entry: FlowEntry) -> some View {
        let selected = studio.selectedSlug == entry.slug
        return Button {
            requestOpen(entry)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.white : Theme.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(Theme.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Theme.primaryText)
                        .lineLimit(1).truncationMode(.middle)
                    Text(entry.slug)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Theme.mutedText)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func requestOpen(_ entry: FlowEntry) {
        if studio.selectedSlug == entry.slug { return }
        if studio.isDirty { pendingSwitchTo = entry } else { studio.open(entry) }
    }

    /// Drains `studio.pendingOpen` (set by external callers, e.g. Library's
    /// "Edit in Studio" handoff). Routes through `requestOpen` so dirty edits
    /// trigger the discard alert instead of being clobbered silently.
    private func drainPendingOpen() {
        guard let target = studio.pendingOpen else { return }
        studio.pendingOpen = nil
        requestOpen(target)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if studio.selectedSlug == nil {
            emptyState
        } else if let error = studio.loadError {
            loadErrorView(error)
        } else if studio.document != nil, let entry = currentEntry {
            editor(for: entry)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentEntry: FlowEntry? {
        guard let slug = studio.selectedSlug else { return nil }
        return savedFlows.first { $0.slug == slug }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentGlow).frame(width: 110, height: 110).blur(radius: 14)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 56)).foregroundStyle(Theme.accent)
            }
            Text("Studio").font(Theme.title).foregroundStyle(Theme.primaryText)
            Text("Pick a flow on the left to edit it.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(Theme.body).foregroundStyle(Theme.stopped)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            if let entry = currentEntry {
                Button("Retry") { studio.open(entry) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for entry: FlowEntry) -> some View {
        VStack(spacing: 0) {
            editorHeader(for: entry)
            Divider().overlay(Theme.separator)
            switch viewMode {
            case .timeline:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nameAndDescription
                        stepsSection(for: entry)
                        parametersSection
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .canvas:
                FlowCanvasView(studio: studio, entry: entry, editable: isEditingEnabled)
            }
            Divider().overlay(Theme.separator)
            editorFooter(for: entry)
        }
    }

    private func editorHeader(for entry: FlowEntry) -> some View {
        let title: String = {
            let docName = studio.document?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let docName, !docName.isEmpty { return docName }
            return entry.name
        }()
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.title).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(entry.slug).font(Theme.caption).foregroundStyle(Theme.mutedText).lineLimit(1)
            }
            Spacer(minLength: 8)
            viewModePicker
            if studio.isDirty {
                Text("Unsaved").font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accentGlow, in: Capsule())
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([entry.path]) } label: {
                Image(systemName: "folder")
            }
            .help("Open in Finder").buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(EditorViewMode.allCases) { mode in
                Label(mode.label, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
        .help("Switch between the vertical timeline and the freestyle canvas")
    }

    @ViewBuilder
    private var nameAndDescription: some View {
        if let doc = Binding(unwrap: $studio.document) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(Theme.caption).foregroundStyle(Theme.mutedText)
                    TextField("Skill name", text: doc.name)
                        .textFieldStyle(.plain)
                        .font(Theme.headline).foregroundStyle(Theme.primaryText)
                        .padding(8)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                        .disabled(!isEditingEnabled)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(Theme.caption).foregroundStyle(Theme.mutedText)
                    TextField("When should Claude reach for this skill?",
                              text: doc.flowDescription, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...6)
                        .font(Theme.body).foregroundStyle(Theme.secondaryText)
                        .padding(8)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                        .disabled(!isEditingEnabled)
                }
            }
        }
    }

    @ViewBuilder
    private func stepsSection(for entry: FlowEntry) -> some View {
        if let doc = Binding(unwrap: $studio.document) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Steps").font(Theme.headline).foregroundStyle(Theme.primaryText)
                    Text("\(doc.wrappedValue.steps.count)").font(Theme.caption).foregroundStyle(Theme.mutedText)
                    Spacer()
                }
                if doc.wrappedValue.steps.isEmpty {
                    Text("No steps in this flow.")
                        .font(Theme.body).foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(doc.wrappedValue.steps.enumerated()), id: \.element.id) { idx, _ in
                            FlowStepCard(step: doc.steps[idx],
                                         index: idx + 1,
                                         skillDir: entry.path,
                                         editable: isEditingEnabled,
                                         canMoveUp: studio.canMoveStepUp(at: idx),
                                         canMoveDown: studio.canMoveStepDown(at: idx),
                                         onMoveUp: { studio.moveStepUp(at: idx) },
                                         onMoveDown: { studio.moveStepDown(at: idx) })
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var parametersSection: some View {
        if let doc = Binding(unwrap: $studio.document) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Parameters").font(Theme.headline).foregroundStyle(Theme.primaryText)
                    Text("\(doc.wrappedValue.parameters.count)").font(Theme.caption).foregroundStyle(Theme.mutedText)
                    Spacer()
                    if isEditingEnabled {
                        Button {
                            let existing = Set(doc.wrappedValue.parameters.map(\.name))
                            var name = "new_parameter"
                            var i = 2
                            while existing.contains(name) { name = "new_parameter_\(i)"; i += 1 }
                            doc.parameters.wrappedValue.append(.init(
                                name: name, type: "string", description: nil,
                                defaultValue: .string(""), autoDetected: false))
                        } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).font(Theme.caption)
                    }
                }
                if doc.wrappedValue.parameters.isEmpty {
                    Text("No parameters — this skill runs the same way every time.")
                        .font(Theme.body).foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    VStack(spacing: 10) {
                        // Index-based identity — Parameter.id is the user-editable name,
                        // which can transiently duplicate (e.g. clicking "Add" twice both
                        // produce name="new_parameter") and bind-by-id would crash ForEach.
                        ForEach(Array(doc.wrappedValue.parameters.enumerated()), id: \.offset) { idx, _ in
                            FlowParameterCard(parameter: doc.parameters[idx],
                                              editable: isEditingEnabled,
                                              onRemove: isEditingEnabled ? { doc.parameters.wrappedValue.remove(at: idx) } : nil)
                        }
                    }
                }
            }
        }
    }

    private func editorFooter(for entry: FlowEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            footerStatusLine
            HStack(spacing: 10) {
                Spacer(minLength: 12)
                nlEditButton(for: entry)
                regenerateButton(for: entry)
                Button("Discard") { studio.discard() }
                    .buttonStyle(.bordered)
                    .disabled(!studio.isDirty || studio.isAsyncRunning)
                Button("Save") { studio.save(for: entry) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(!studio.isDirty || studio.isAsyncRunning)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .sheet(isPresented: $showingNLEditor) {
            nlEditorSheet(for: entry)
        }
    }

    @ViewBuilder
    private func nlEditButton(for entry: FlowEntry) -> some View {
        let running = studio.nlEditState == .running || studio.regenerateState == .running
        Button {
            nlEditorInstruction = ""
            showingNLEditor = true
        } label: {
            Label("Edit with AI…", systemImage: "wand.and.stars")
        }
        .buttonStyle(.bordered)
        .disabled(running || studio.isDirty)
        .help(studio.isDirty
              ? "Save your edits first — the AI edit reads flow.json from disk."
              : "Describe a change in plain English; the runtime rewrites flow.json.")
    }

    @ViewBuilder
    private func nlEditorSheet(for entry: FlowEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Edit with AI", systemImage: "wand.and.stars")
                .font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text("Describe a change. The runtime will read this flow's flow.json, apply the smallest edit that satisfies your instruction, and write the result back.")
                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $nlEditorInstruction)
                .font(Theme.body).foregroundStyle(Theme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 110)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
            Text("Examples: “rename step 3 to log into Firefox”, “add a notes field to the verify step”, “mark the last step as inferred”.")
                .font(.caption2).foregroundStyle(Theme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { showingNLEditor = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    let instruction = nlEditorInstruction
                    showingNLEditor = false
                    Task { await studio.editWithInstruction(for: entry, instruction: instruction) }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(nlEditorInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 540, minHeight: 280, idealHeight: 320)
        .background(Theme.paneBackground)
    }

    @ViewBuilder
    private var footerStatusLine: some View {
        // Precedence: live progress beats stale errors. Without this, a prior
        // saveError would mask the running spinner during a long NL edit.
        if studio.nlEditState == .running {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Applying AI edit…").font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }
        } else if studio.regenerateState == .running {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Regenerating SKILL.md…").font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }
        } else if let error = studio.saveError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(Theme.caption).foregroundStyle(Theme.stopped).lineLimit(2)
        } else if case .failure(let msg) = studio.nlEditState {
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(Theme.caption).foregroundStyle(Theme.stopped).lineLimit(2)
        } else if case .failure(let msg) = studio.regenerateState {
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(Theme.caption).foregroundStyle(Theme.stopped).lineLimit(2)
        } else if case .success = studio.nlEditState {
            Label("Edit applied — flow.json reloaded.", systemImage: "checkmark.circle.fill")
                .font(Theme.caption).foregroundStyle(Theme.recording)
        } else if case .success = studio.regenerateState {
            Label("SKILL.md regenerated.", systemImage: "checkmark.circle.fill")
                .font(Theme.caption).foregroundStyle(Theme.recording)
        }
    }

    @ViewBuilder
    private func regenerateButton(for entry: FlowEntry) -> some View {
        // Block while either runtime-spawning action is in flight — they both
        // operate on flow.json / SKILL.md on disk, so concurrent runs race.
        let running = studio.regenerateState == .running || studio.nlEditState == .running
        Button {
            Task { await studio.regenerate(for: entry) }
        } label: {
            Label("Regenerate SKILL.md", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .disabled(running || studio.isDirty)
        .help(studio.isDirty
              ? "Save your edits first — regen reads flow.json from disk."
              : "Re-run the synthesis runtime to rewrite SKILL.md from this flow.json.")
    }
}

// MARK: - Step card

private struct FlowStepCard: View {
    @Binding var step: FlowDocument.Step
    let index: Int
    let skillDir: URL
    let editable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Divider().overlay(Theme.separator)
                if step.frameRelativePath != nil { thumbnail }
                intentField
                appField
                inferredToggle
                notesField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editable { reorderColumn }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())
            Text(step.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.mutedText)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if step.inferred {
                Text("inferred")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.paused)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.cardBackground, in: Capsule())
                    .overlay(Capsule().stroke(Theme.paused.opacity(0.4)))
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let rel = step.frameRelativePath {
            let url = skillDir.appendingPathComponent(rel)
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack { ProgressView().controlSize(.small) }
                        .frame(maxWidth: .infinity).frame(height: 90)
                case .success(let image):
                    image.resizable().scaledToFit().frame(maxHeight: 140)
                        .frame(maxWidth: .infinity, alignment: .center)
                case .failure:
                    Label("Missing screenshot: \(rel)", systemImage: "photo")
                        .font(Theme.caption).foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                @unknown default: EmptyView()
                }
            }
            .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var reorderColumn: some View {
        VStack(spacing: 6) {
            Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).foregroundStyle(canMoveUp ? Theme.secondaryText : Theme.mutedText)
                .disabled(!canMoveUp).help("Move step up")
            Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).foregroundStyle(canMoveDown ? Theme.secondaryText : Theme.mutedText)
                .disabled(!canMoveDown).help("Move step down")
        }
        .frame(width: 22)
        .padding(.top, 2)
    }

    private var intentField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Intent").font(.caption2).foregroundStyle(Theme.mutedText)
            TextField("What is the user trying to do in this step?",
                      text: $step.intent, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...8)
                .font(Theme.body).foregroundStyle(Theme.primaryText)
                .padding(8)
                .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                .disabled(!editable)
        }
    }

    private var appField: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.dashed").foregroundStyle(Theme.mutedText)
            TextField("App (optional)",
                      text: Binding(get: { step.app ?? "" },
                                    set: { step.app = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.plain)
                .font(Theme.body).foregroundStyle(Theme.secondaryText)
                .padding(6)
                .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                .disabled(!editable)
        }
    }

    private var inferredToggle: some View {
        HStack {
            Toggle(isOn: $step.inferred) {
                Text("Inferred").font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }
            .toggleStyle(.switch).controlSize(.small).labelsHidden()
            Text("Inferred — verify before relying on this step")
                .font(Theme.caption).foregroundStyle(Theme.mutedText)
            Spacer(minLength: 0)
        }
        .opacity(editable ? 1 : 0.6)
        .disabled(!editable)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes").font(.caption2).foregroundStyle(Theme.mutedText)
            TextField("Optional notes for this step.",
                      text: Binding(get: { step.notes ?? "" },
                                    set: { step.notes = $0.isEmpty ? nil : $0 }),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(Theme.body).foregroundStyle(Theme.secondaryText)
                .padding(8)
                .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                .disabled(!editable)
        }
    }
}

// MARK: - Parameter card

private struct FlowParameterCard: View {
    @Binding var parameter: FlowDocument.Parameter
    let editable: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.mutedText)
                TextField("name", text: $parameter.name)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.primaryText)
                    .padding(6)
                    .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                    .frame(maxWidth: 220)
                    .disabled(!editable)
                if let type = parameter.type, !type.isEmpty {
                    Text(type).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.cardBackground, in: Capsule())
                        .overlay(Capsule().stroke(Theme.separator))
                }
                if parameter.autoDetected {
                    Text("auto").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.paused)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.cardBackground, in: Capsule())
                        .overlay(Capsule().stroke(Theme.paused.opacity(0.4)))
                }
                Spacer(minLength: 0)
                if let onRemove {
                    Button { onRemove() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(Theme.mutedText)
                        .help("Remove parameter")
                }
            }
            descriptionField
            defaultField
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description").font(.caption2).foregroundStyle(Theme.mutedText)
            TextField("What does this parameter control?",
                      text: Binding(get: { parameter.description ?? "" },
                                    set: { parameter.description = $0.isEmpty ? nil : $0 }),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .font(Theme.body).foregroundStyle(Theme.secondaryText)
                .padding(8)
                .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                .disabled(!editable)
        }
    }

    @ViewBuilder
    private var defaultField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Default").font(.caption2).foregroundStyle(Theme.mutedText)
            if parameter.defaultIsEditableScalar {
                TextField("Default value", text: Binding(
                    get: { parameter.defaultDisplay },
                    set: { parameter.setDefaultFromText($0) }))
                    .textFieldStyle(.plain)
                    .font(Theme.body).foregroundStyle(Theme.primaryText)
                    .padding(8)
                    .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                    .disabled(!editable)
            } else {
                Text(parameter.defaultDisplay)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
                Text("Structured default — edit flow.json directly to change.")
                    .font(.caption2).foregroundStyle(Theme.mutedText)
            }
        }
    }
}

// MARK: - Binding helpers

/// `Binding<T?>` isn't `Sendable`, but `Binding.init(get:set:)` wants `@Sendable`
/// closures under Swift 6 — wrap the source in an `@unchecked Sendable` box so
/// SwiftUI gets its sendability promise. Safe in practice: SwiftUI confines
/// binding access to the main actor. The fallback value guards against the
/// (rare) case where the source goes nil between view construction and a
/// later get/set fire — without crashing.
private final class BindingBox<T>: @unchecked Sendable {
    let source: Binding<T?>
    let fallback: T
    init(_ s: Binding<T?>, fallback: T) { self.source = s; self.fallback = fallback }
}

extension Binding {
    /// Unwraps `Binding<T?>` to `Binding<T>?` when the optional has a value.
    /// Lets views bind into `studio.document` without force-unwraps.
    init?(unwrap source: Binding<Value?>) {
        guard let initial = source.wrappedValue else { return nil }
        let box = BindingBox(source, fallback: initial)
        self.init(
            get: { box.source.wrappedValue ?? box.fallback },
            // No-op if the source went nil — SwiftUI's view tree will tear
            // this binding down on the next render anyway.
            set: { if box.source.wrappedValue != nil { box.source.wrappedValue = $0 } }
        )
    }
}
