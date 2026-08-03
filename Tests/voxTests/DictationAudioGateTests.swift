import XCTest
@testable import vox

final class DictationAudioGateTests: XCTestCase {

    // MARK: - Silence gate (thresholds tuned from empty-hold log failures)

    func testSilenceGateSkipsSubHalfSecondClips() {
        // Lived bug: 0.37s ambient (rms ~200) passed the old 0.35s floor and
        // produced "ls -l" / pangram hallucinations.
        XCTAssertTrue(DictationSilenceGate.shouldSkip(durationSec: 0.37, rms: 210))
        XCTAssertTrue(DictationSilenceGate.shouldSkip(durationSec: 0.49, rms: 2000))
        XCTAssertFalse(DictationSilenceGate.shouldSkip(durationSec: 0.50, rms: 400))
    }

    func testSilenceGateSkipsQuietShortClips() {
        // Lived bug: 0.74s @ rms 301 → "The cat sat on the mat."
        XCTAssertTrue(DictationSilenceGate.shouldSkip(durationSec: 0.74, rms: 301))
        XCTAssertTrue(DictationSilenceGate.shouldSkip(durationSec: 1.5, rms: 349))
        XCTAssertFalse(DictationSilenceGate.shouldSkip(durationSec: 1.5, rms: 350))
    }

    func testSilenceGateAllowsRealShortSpeech() {
        // Real command holds from history: ~1.3s+ with rms 600–1100.
        XCTAssertFalse(DictationSilenceGate.shouldSkip(durationSec: 1.37, rms: 978))
        XCTAssertFalse(DictationSilenceGate.shouldSkip(durationSec: 2.5, rms: 80))
    }

    func testSilenceGateSkipsNearDigitalSilence() {
        XCTAssertTrue(DictationSilenceGate.shouldSkip(durationSec: 5.0, rms: 39))
        XCTAssertFalse(DictationSilenceGate.shouldSkip(durationSec: 5.0, rms: 40))
    }

    // MARK: - Hallucination / prompt-echo suppress

    func testSuppressesProsePangramFiller() {
        XCTAssertTrue(DictationHallucinationGuard.shouldSuppress(
            "The quick brown fox jumps over the lazy dog.",
            mode: .prose,
            durationSec: 0.37,
            rms: 210
        ))
    }

    func testSuppressesCatSatFiller() {
        XCTAssertTrue(DictationHallucinationGuard.shouldSuppress(
            "The cat sat on the mat.",
            mode: .prose,
            durationSec: 0.74,
            rms: 301
        ))
    }

    func testSuppressesCommandPromptEchoOnShortQuietClip() {
        XCTAssertTrue(DictationHallucinationGuard.shouldSuppress(
            "ls -l",
            mode: .command,
            durationSec: 0.37,
            rms: 202
        ))
    }

    func testAllowsRealSpokenCommandMatchingPromptExample() {
        // Same text, but duration/RMS match real speech — do not suppress.
        XCTAssertFalse(DictationHallucinationGuard.shouldSuppress(
            "ls -l",
            mode: .command,
            durationSec: 1.2,
            rms: 800
        ))
    }

    func testDoesNotSuppressOrdinaryProse() {
        XCTAssertFalse(DictationHallucinationGuard.shouldSuppress(
            "When triggering the recording, sometimes I don't say anything.",
            mode: .prose,
            durationSec: 0.37,
            rms: 210
        ))
    }

    func testNormalizeStripsPunctuationForMatching() {
        XCTAssertEqual(
            DictationHallucinationGuard.normalize("LS -l."),
            "ls l"
        )
        XCTAssertTrue(DictationHallucinationGuard.promptEchoCommands.contains("ls l"))
    }
}
