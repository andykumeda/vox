import XCTest
@testable import vox

final class SilenceTrimTests: XCTestCase {

    // MARK: - hasAudibleContent guard semantics

    func testHasAudibleContentRequiresSamplesAboveThreshold() {
        // Pre-fix bug: silent file longer than 100ms returned (0, totalDur)
        // and `hasAudibleContent` was true because duration > 0.1s. This
        // sent pure silence to Whisper and produced hallucinated text.
        let silent = AudibleBounds(
            firstAudibleSec: 0,
            lastAudibleSec: 60.0,
            totalDurationSec: 60.0,
            hadAudibleSamples: false
        )
        XCTAssertFalse(silent.hasAudibleContent,
                       "Silent file (no samples above threshold) must not be reported as audible.")
    }

    func testHasAudibleContentTrueWhenSamplesAndDurationOK() {
        let real = AudibleBounds(
            firstAudibleSec: 1.0,
            lastAudibleSec: 5.0,
            totalDurationSec: 10.0,
            hadAudibleSamples: true
        )
        XCTAssertTrue(real.hasAudibleContent)
    }

    func testHasAudibleContentRequiresAtLeast100msDuration() {
        // Even with samples, duration <= 100ms is treated as no content.
        let blip = AudibleBounds(
            firstAudibleSec: 1.0,
            lastAudibleSec: 1.05,  // 50ms
            totalDurationSec: 10.0,
            hadAudibleSamples: true
        )
        XCTAssertFalse(blip.hasAudibleContent)
    }
}
