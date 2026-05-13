import Foundation

/// Serializes a finished `FlowSession` to a manifest JSON consumed by `claude -p`.
/// Ported from V1's `ScreenpipeFlow/ManifestWriter`; `manifestVersion: 1`.
enum ManifestWriter {
    struct RegenerationContext {
        let previousSkillPath: URL
        let userFeedback: String
    }

    enum WriteError: Error {
        case sessionNotEnded
    }

    /// Writes a manifest JSON to `<manifestsDir>/<uuid>.json` and returns its URL.
    @MainActor
    static func write(
        session: FlowSession,
        outputDir: URL,
        userHintsName: String?,
        userHintsDescription: String?,
        userHintsNotes: String?,
        regenerationContext: RegenerationContext?,
        manifestsDir: URL
    ) throws -> URL {
        guard session.endTime != nil else { throw WriteError.sessionNotEnded }
        try FileManager.default.createDirectory(at: manifestsDir, withIntermediateDirectories: true)

        let manifestId = UUID().uuidString
        let url = manifestsDir.appendingPathComponent("\(manifestId).json")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        // `nil as Any` wraps the Optional, which JSONSerialization can't encode.
        // Map missing strings to NSNull explicitly so they serialize as JSON `null`.
        let hints: [String: Any] = [
            "name": userHintsName.map { $0 as Any } ?? NSNull(),
            "description": userHintsDescription.map { $0 as Any } ?? NSNull(),
            "notes": userHintsNotes.map { $0 as Any } ?? NSNull()
        ]

        var dict: [String: Any] = [
            "manifestVersion": 1,
            "manifestId": manifestId,
            "createdAt": iso.string(from: Date()),
            "mode": session.mode.rawValue,
            "timeRange": [
                "start": iso.string(from: session.timeRangeStart),
                "end": iso.string(from: session.timeRangeEnd)
            ],
            "activeRecordingStart": iso.string(from: session.activeRecordingStart),
            "userHints": hints,
            "outputDir": outputDir.path,
            "regenerationContext": NSNull()
        ]
        if let regen = regenerationContext {
            dict["regenerationContext"] = [
                "previousSkillPath": regen.previousSkillPath.path,
                "userFeedback": regen.userFeedback
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }
}
