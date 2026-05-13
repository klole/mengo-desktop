import XCTest
@testable import MengoDesktop

final class RecordingSourcesStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "MengoTest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_defaults_areNil() {
        let store = RecordingSourcesStore(defaults: freshDefaults())
        XCTAssertNil(store.selectedMonitorIDs)
        XCTAssertNil(store.selectedAudioDeviceNames)
    }

    func test_monitorIDs_roundTrip_includingEmpty() {
        let store = RecordingSourcesStore(defaults: freshDefaults())
        store.selectedMonitorIDs = [1, 2]
        XCTAssertEqual(store.selectedMonitorIDs, [1, 2])
        store.selectedMonitorIDs = []
        XCTAssertEqual(store.selectedMonitorIDs, [])     // empty, not nil
        store.selectedMonitorIDs = nil
        XCTAssertNil(store.selectedMonitorIDs)
    }

    func test_audioNames_roundTrip_emptyDistinctFromNil() {
        let store = RecordingSourcesStore(defaults: freshDefaults())
        XCTAssertNil(store.selectedAudioDeviceNames)
        store.selectedAudioDeviceNames = []
        XCTAssertEqual(store.selectedAudioDeviceNames, [])
        store.selectedAudioDeviceNames = ["MacBook Pro Microphone (input)"]
        XCTAssertEqual(store.selectedAudioDeviceNames, ["MacBook Pro Microphone (input)"])
        store.selectedAudioDeviceNames = nil
        XCTAssertNil(store.selectedAudioDeviceNames)
    }

    func test_persistsAcrossInstances() {
        let d = freshDefaults()
        RecordingSourcesStore(defaults: d).selectedMonitorIDs = [3]
        XCTAssertEqual(RecordingSourcesStore(defaults: d).selectedMonitorIDs, [3])
    }
}
