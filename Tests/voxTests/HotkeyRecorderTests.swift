import XCTest
@testable import vox

@MainActor
final class HotkeyRecorderTests: XCTestCase {
    func testOnlyOneRecorderCanCaptureAtATime() {
        let first = HotkeyRecorder(existingTriggerMode: .pressHold)
        let second = HotkeyRecorder(existingTriggerMode: .pressHold)
        defer {
            first.cancel()
            second.cancel()
        }

        XCTAssertTrue(first.start { _ in })
        XCTAssertFalse(second.start { _ in })
    }

    func testDeinitStopsCapturingWhenFieldDisappears() {
        weak var releasedRecorder: HotkeyRecorder?

        autoreleasepool {
            let recorder = HotkeyRecorder(existingTriggerMode: .pressHold)
            releasedRecorder = recorder
            XCTAssertTrue(recorder.start { _ in })
        }

        XCTAssertNil(releasedRecorder)
        XCTAssertFalse(HotkeyRecorder.isCapturing)
    }
}
