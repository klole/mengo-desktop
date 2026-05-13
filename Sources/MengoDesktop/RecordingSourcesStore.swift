import Foundation

/// Persists which displays / microphones the user wants recorded.
///
/// `nil` means "leave it to screenpipe's default" — all monitors / default mic +
/// system audio — so an untouched install records exactly as it ships. An
/// explicitly **empty** `selectedAudioDeviceNames` means "no audio" (`--disable-audio`),
/// which is why it's stored distinctly from `nil`. Monitor IDs are re-validated
/// against the live display list at spawn time (see `RecorderController`).
struct RecordingSourcesStore {
    private let defaults: UserDefaults
    private let monitorKey = "recording.selectedMonitorIDs"
    private let audioKey = "recording.selectedAudioDeviceNames"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var selectedMonitorIDs: [Int]? {
        get { defaults.array(forKey: monitorKey) as? [Int] }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: monitorKey) }
            else { defaults.removeObject(forKey: monitorKey) }
        }
    }

    var selectedAudioDeviceNames: [String]? {
        get { defaults.array(forKey: audioKey) as? [String] }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: audioKey) }
            else { defaults.removeObject(forKey: audioKey) }
        }
    }
}
