import Foundation
import Observation

/// Backing store for the Studio pane. Owns the currently-open `FlowDocument`,
/// tracks dirty state against the on-disk version, and writes edits back to
/// `flow.json` on Save. Editability while async work is running is enforced
/// in the view layer (see `StudioPane`).
@Observable
@MainActor
final class StudioController {

    enum RegenerateState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    /// Same shape as `RegenerateState` — kept as a separate enum so the UI can
    /// surface independent banners for "edit succeeded" vs "regen succeeded".
    enum NLEditState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    /// Slug of the flow currently shown in the editor. `nil` when nothing is
    /// open (empty state). Owned by the controller so it survives sidebar
    /// section switches.
    private(set) var selectedSlug: String?

    /// The editing buffer. `nil` means nothing is loaded.
    var document: FlowDocument?

    /// Loaded-from-disk snapshot, used for `isDirty` and Discard.
    private(set) var pristine: FlowDocument?

    private(set) var loadError: String?
    private(set) var saveError: String?
    private(set) var regenerateState: RegenerateState = .idle
    private(set) var nlEditState: NLEditState = .idle

    /// External request to open a flow (set by callers outside Studio, e.g.
    /// the "Edit in Studio" button in Library). `StudioPane` drains this on
    /// appear/change so the dirty-discard alert is honored before clobbering
    /// in-progress edits.
    var pendingOpen: FlowEntry?

    /// Async regen action. Owned by the app entry, which wires it to
    /// `SkillMdRegenerator`. `nil` here just means "Regenerate" is disabled
    /// (e.g. in tests that don't need it).
    @ObservationIgnored var regenerator: (@MainActor (URL) async -> Result<Void, Error>)?

    /// Async NL-edit action. App entry wires it to `NaturalLanguageEditor`.
    /// `(skillDir, instruction, optional step id) -> Result`. `nil` disables
    /// the "Edit with AI" UI.
    @ObservationIgnored var nlEditor: (@MainActor (URL, String, String?) async -> Result<Void, Error>)?

    var isDirty: Bool {
        guard let document, let pristine else { return false }
        return document != pristine
    }

    /// True while a runtime-spawning action (regenerate, NL edit) is in flight.
    /// The UI uses this to lock every editable control — both actions write to
    /// `flow.json` on disk, and the NL-edit success path reloads the document,
    /// silently overwriting any concurrent in-memory edits if we don't gate.
    var isAsyncRunning: Bool {
        regenerateState == .running || nlEditState == .running
    }

    /// Opens a flow's `flow.json` into the editor. Returns `false` on parse
    /// errors (and surfaces them via `loadError`).
    @discardableResult
    func open(_ entry: FlowEntry) -> Bool {
        selectedSlug = entry.slug
        saveError = nil
        regenerateState = .idle
        nlEditState = .idle
        let url = entry.path.appendingPathComponent("flow.json")
        do {
            let doc = try FlowDocument.load(from: url)
            document = doc
            pristine = doc
            loadError = nil
            return true
        } catch let e as FlowDocumentError {
            document = nil; pristine = nil
            loadError = e.errorDescription ?? "Couldn't load flow."
            return false
        } catch {
            document = nil; pristine = nil
            loadError = error.localizedDescription
            return false
        }
    }

    // MARK: - Editing helpers

    /// Move a step within the buffer. Index-checked — out-of-range calls are no-ops.
    /// `destination` is interpreted against the array *after* the source is
    /// removed (i.e. it's an insertion index in `[0, count]`), then clamped
    /// to that range.
    func moveStep(from source: Int, to destination: Int) {
        guard var doc = document, source != destination else { return }
        guard doc.steps.indices.contains(source) else { return }
        let item = doc.steps.remove(at: source)
        let target = max(0, min(destination, doc.steps.count))
        doc.steps.insert(item, at: target)
        document = doc
    }

    /// Convenience helpers for ↑/↓ buttons in the UI.
    func moveStepUp(at index: Int)   { moveStep(from: index, to: index - 1) }
    func moveStepDown(at index: Int) { moveStep(from: index, to: index + 1) }

    func canMoveStepUp(at index: Int) -> Bool   { index > 0 && (document?.steps.indices.contains(index) ?? false) }
    func canMoveStepDown(at index: Int) -> Bool {
        guard let steps = document?.steps else { return false }
        return index >= 0 && index < steps.count - 1
    }

    // MARK: - Canvas mutations

    /// Persist a step's canvas position. Setting `to` to nil reverts to
    /// auto-layout (i.e. removes the explicit position).
    func updateStepPosition(id: String, to position: FlowDocument.StepPosition?) {
        guard var doc = document,
              let idx = doc.steps.firstIndex(where: { $0.id == id }) else { return }
        if doc.steps[idx].position != position {
            doc.steps[idx].position = position
            document = doc
        }
    }

    /// Add an edge from `sourceId` to `targetId`. The first explicit edge on a
    /// source replaces its implicit linear edge; subsequent edges accumulate
    /// (branching). Self-edges and duplicates are no-ops.
    func addEdge(from sourceId: String, to targetId: String) {
        guard sourceId != targetId else { return }
        guard var doc = document,
              let srcIdx = doc.steps.firstIndex(where: { $0.id == sourceId }),
              doc.steps.contains(where: { $0.id == targetId }) else { return }
        var next = doc.steps[srcIdx].explicitNext ?? []
        guard !next.contains(targetId) else { return }
        next.append(targetId)
        doc.steps[srcIdx].explicitNext = next
        document = doc
    }

    /// Restore the linear default connection for `sourceId` by clearing its
    /// explicit-next override. Counterpart to deleting an implicit edge —
    /// gives the user a way back to the array-order default without hand-
    /// editing flow.json.
    func restoreLinearDefault(for sourceId: String) {
        guard var doc = document,
              let idx = doc.steps.firstIndex(where: { $0.id == sourceId }) else { return }
        if doc.steps[idx].explicitNext != nil {
            doc.steps[idx].explicitNext = nil
            document = doc
        }
    }

    /// Remove an edge. Two cases:
    ///   - Source has explicit next: just remove the target. Even if the list
    ///     becomes empty, the source still has `explicitNext = []`, which
    ///     `FlowDocument.edges()` reads as "no successors" — the linear
    ///     default stays suppressed.
    ///   - Source has nil explicit next (implicit linear edge): stamp `[]` to
    ///     suppress the default. Per `edges()` invariants, the only way the UI
    ///     surfaces an "implicit" edge is when this branch applies, so we never
    ///     reach this case for a step that already has explicit successors.
    func removeEdge(from sourceId: String, to targetId: String) {
        guard var doc = document,
              let srcIdx = doc.steps.firstIndex(where: { $0.id == sourceId }) else { return }
        if var next = doc.steps[srcIdx].explicitNext {
            next.removeAll { $0 == targetId }
            doc.steps[srcIdx].explicitNext = next
        } else {
            doc.steps[srcIdx].explicitNext = []
        }
        document = doc
    }

    /// Drops the current selection (empty state). Caller is responsible for
    /// checking `isDirty` and confirming with the user first.
    func close() {
        selectedSlug = nil
        document = nil
        pristine = nil
        loadError = nil
        saveError = nil
    }

    /// If the user deleted the open flow, or the library refreshed and the
    /// slug is gone, drop it.
    func reconcile(library: [FlowEntry]) {
        guard let slug = selectedSlug else { return }
        if !library.contains(where: { $0.slug == slug && $0.exists }) {
            close()
        }
    }

    /// Resets the buffer to the on-disk version.
    func discard() {
        document = pristine
        saveError = nil
    }

    /// Writes the buffer back to `flow.json`. Atomic write — partial failures
    /// can't corrupt the source file.
    func save(for entry: FlowEntry) {
        guard let document else { return }
        let url = entry.path.appendingPathComponent("flow.json")
        do {
            try document.save(to: url)
            pristine = document
            saveError = nil
            // A successful save invalidates any prior async-action banners.
            regenerateState = .idle
            nlEditState = .idle
        } catch let e as FlowDocumentError {
            saveError = e.errorDescription ?? "Couldn't save flow."
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Applies a natural-language edit to flow.json via the wired `nlEditor`.
    /// Callers should save dirty buffers first — the runtime reads from disk,
    /// and on success Studio reloads the document (which would otherwise wipe
    /// pending edits). If the user switches flows mid-edit, the result is
    /// dropped (same cross-flow contamination guard as `regenerate(for:)`).
    func editWithInstruction(for entry: FlowEntry, instruction: String, stepId: String? = nil) async {
        guard let nlEditor else {
            nlEditState = .failure("Edit isn't wired up.")
            return
        }
        // Belt-and-suspenders: the UI already disables the button when dirty,
        // but if the controller is called with a dirty buffer the reload below
        // would clobber the user's pending edits. Refuse instead.
        if isDirty {
            nlEditState = .failure("Save your edits before applying an AI edit.")
            return
        }
        let flowURL = entry.path.appendingPathComponent("flow.json")
        let backupURL = entry.path.appendingPathComponent("flow.json.bak")
        // Snapshot the on-disk file so a model that writes invalid JSON
        // can be rolled back without manual recovery.
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: flowURL, to: backupURL)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let startedFor = entry.slug
        nlEditState = .running
        let result = await nlEditor(entry.path, instruction, stepId)
        guard selectedSlug == startedFor else { return }
        switch result {
        case .success:
            do {
                let doc = try FlowDocument.load(from: flowURL)
                document = doc
                pristine = doc
                nlEditState = .success
            } catch let e as FlowDocumentError {
                // Model wrote unreadable JSON — restore the pre-edit backup so
                // the user isn't left with a corrupt flow.json on disk.
                try? FileManager.default.removeItem(at: flowURL)
                try? FileManager.default.copyItem(at: backupURL, to: flowURL)
                nlEditState = .failure("Edit produced invalid flow.json — restored from backup. (\(e.errorDescription ?? "parse error"))")
            } catch {
                try? FileManager.default.removeItem(at: flowURL)
                try? FileManager.default.copyItem(at: backupURL, to: flowURL)
                nlEditState = .failure("Edit succeeded but reload failed — restored from backup. (\(error.localizedDescription))")
            }
        case .failure(let error):
            nlEditState = .failure((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// Triggers SKILL.md regeneration against the on-disk flow.json (callers
    /// should save dirty buffers first). Runs the wired `regenerator` closure
    /// off the main actor; updates `regenerateState` for the UI.
    ///
    /// If the user switches flows while regen is in flight, the result is
    /// dropped — Studio's status banner is global, and applying a stale
    /// success/failure to a different flow would mislead the user.
    func regenerate(for entry: FlowEntry) async {
        guard let regenerator else {
            regenerateState = .failure("Regenerate isn't wired up.")
            return
        }
        let startedFor = entry.slug
        regenerateState = .running
        let result = await regenerator(entry.path)
        guard selectedSlug == startedFor else { return }
        switch result {
        case .success:
            regenerateState = .success
        case .failure(let error):
            regenerateState = .failure((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}
