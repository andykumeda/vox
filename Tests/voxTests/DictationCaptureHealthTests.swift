import XCTest
@testable import vox

final class DictationCaptureHealthTests: XCTestCase {
    func testSuccessfulEngineStartWithoutFramesIsNotRecording() {
        let progress = DictationCaptureProgress(startedAt: 10)
        XCTAssertEqual(progress.health(at: 11, timeout: 2), .starting)
        guard case .failed = progress.health(at: 12, timeout: 2) else {
            return XCTFail("A header-only recording must fail, not look like silence")
        }
    }

    func testQuietFramesKeepCaptureHealthyAndMissingFramesFail() {
        var progress = DictationCaptureProgress(startedAt: 10)
        progress.lastFrameAt = 30
        XCTAssertEqual(progress.health(at: 31, timeout: 2), .receiving)
        guard case .failed = progress.health(at: 32, timeout: 2) else {
            return XCTFail("Mid-recording stall must fail")
        }
    }

    func testConversionAndWriteFailuresAreNotSilence() {
        var progress = DictationCaptureProgress(startedAt: 10)
        progress.lastFrameAt = 11
        progress.failure = "Conversion failed"
        XCTAssertEqual(progress.health(at: 11, timeout: 2), .failed("Conversion failed"))
    }
}
