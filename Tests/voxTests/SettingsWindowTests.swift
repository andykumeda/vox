import XCTest
@testable import vox

final class SettingsWindowTests: XCTestCase {
    func testRecordingStorageUsageFormatsBothCategoriesFromSnapshot() {
        let usage = RecordingStorageUsage(
            dictationBytes: 2_048,
            meetingBytes: 8_192
        )

        let line = usage.formatted { "\($0) bytes" }

        XCTAssertEqual(
            line,
            "On disk now: 2048 bytes dictation, 8192 bytes meetings."
        )
    }
}
