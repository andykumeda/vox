import XCTest
@testable import vox

final class MeetingMutexTests: XCTestCase {
    override func tearDown() {
        DictationMutex.isBlocked = { false }
        super.tearDown()
    }

    func testMutexBlocksWhenMeetingRecording() {
        DictationMutex.isBlocked = { true }
        XCTAssertTrue(DictationMutex.isBlocked())
    }

    func testMutexDoesNotBlockWhenIdle() {
        DictationMutex.isBlocked = { false }
        XCTAssertFalse(DictationMutex.isBlocked())
    }
}
