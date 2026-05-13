import XCTest
@testable import MengoDesktop

final class RecorderStatusTests: XCTestCase {

    func test_from_mapsTheFourPauseCombos() {
        XCTAssertEqual(RecorderStatus.from(audioPaused: false, screenPaused: false), .recording)
        XCTAssertEqual(RecorderStatus.from(audioPaused: true,  screenPaused: false), .audioPaused)
        XCTAssertEqual(RecorderStatus.from(audioPaused: false, screenPaused: true),  .screenPaused)
        XCTAssertEqual(RecorderStatus.from(audioPaused: true,  screenPaused: true),  .bothPaused)
    }

    func test_isRecording_trueForActiveStates_falseOtherwise() {
        XCTAssertTrue(RecorderStatus.recording.isRecording)
        XCTAssertTrue(RecorderStatus.audioPaused.isRecording)
        XCTAssertTrue(RecorderStatus.screenPaused.isRecording)
        XCTAssertTrue(RecorderStatus.bothPaused.isRecording)
        XCTAssertFalse(RecorderStatus.idle.isRecording)
        XCTAssertFalse(RecorderStatus.starting.isRecording)
        XCTAssertFalse(RecorderStatus.error("x").isRecording)
    }
}
