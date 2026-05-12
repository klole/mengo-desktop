import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case browsingTimeline
        case recording(RecordingSession)
        case synthesizing(URL)        // manifest path
        case reviewing(URL)           // skill directory path
        case error(String)
    }

    enum ScreenpipeStatus: Equatable {
        case unknown
        case running
        case audioPaused
        case unhealthy(String)
    }

    private(set) var sessionState: SessionState = .idle
    private(set) var library: [FlowEntry] = []
    private(set) var screenpipeStatus: ScreenpipeStatus = .unknown

    @ObservationIgnored var lastSession: RecordingSession?
    @ObservationIgnored var lastSkillPath: URL?

    init() {
        loadLibraryFromDisk()
    }

    private var skillsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
    }

    private func loadLibraryFromDisk() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let entries: [FlowEntry] = contents.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            // Only include directories that look like our outputs (SKILL.md + flow.json).
            let skillMD = url.appendingPathComponent("SKILL.md")
            let flowJSON = url.appendingPathComponent("flow.json")
            guard FileManager.default.fileExists(atPath: skillMD.path),
                  FileManager.default.fileExists(atPath: flowJSON.path) else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? Date()
            return FlowEntry(slug: url.lastPathComponent,
                             name: url.lastPathComponent,
                             path: url,
                             createdAt: created)
        }
        library = entries.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Session transitions

    func beginBrowsingTimeline() { sessionState = .browsingTimeline }
    func cancelBrowsingTimeline() { sessionState = .idle }
    func beginRecording(_ session: RecordingSession) { sessionState = .recording(session) }
    func beginSynthesizing(manifest: URL) { sessionState = .synthesizing(manifest) }
    func beginReviewing(skill: URL) { sessionState = .reviewing(skill) }
    func setError(_ message: String) { sessionState = .error(message) }
    func finalize() { sessionState = .idle }

    // MARK: - Library

    func addFlow(_ entry: FlowEntry) {
        library.removeAll { $0.slug == entry.slug }
        library.append(entry)
        library.sort { $0.createdAt > $1.createdAt }
    }

    func removeFlow(slug: String) {
        library.removeAll { $0.slug == slug }
    }

    func reopenFlow(slug: String) {
        guard let entry = library.first(where: { $0.slug == slug }) else { return }
        beginReviewing(skill: entry.path)
    }

    // MARK: - screenpipe status

    func updateScreenpipeStatus(_ status: ScreenpipeStatus) {
        screenpipeStatus = status
    }

    // MARK: - Crash recovery

    private var recoveryDir: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScreenpipeFlow/recovery", isDirectory: true)
    }

    /// Called from applicationWillTerminate. If we're mid-recording, leave a
    /// marker so the next launch can prompt to recover via Mode C.
    func writeRecoveryIfNeeded() {
        guard case .recording(let session) = sessionState else { return }
        try? FileManager.default.createDirectory(at: recoveryDir,
                                                  withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let marker: [String: Any] = [
            "mode": session.mode.rawValue,
            "bufferRangeStart": session.bufferRangeStart.map { iso.string(from: $0) as Any } ?? NSNull(),
            "activeRecordingStart": iso.string(from: session.activeRecordingStart),
            "interruptedAt": iso.string(from: Date())
        ]
        let url = recoveryDir.appendingPathComponent("interrupted-\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: marker,
                                                   options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
            Logger.log("recovery marker written to \(url.path)")
        }
    }

    /// Returns the most recent interrupted-session start time, or nil.
    func loadMostRecentInterruptedStart() -> Date? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: recoveryDir,
            includingPropertiesForKeys: [.creationDateKey]
        ).sorted(by: {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? .distantPast
            return a > b
        }), let first = entries.first else { return nil }
        guard let data = try? Data(contentsOf: first),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startStr = json["activeRecordingStart"] as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: startStr)
    }

    func clearRecoveryMarkers() {
        try? FileManager.default.removeItem(at: recoveryDir)
    }
}
