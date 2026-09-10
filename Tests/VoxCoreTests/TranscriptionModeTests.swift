import XCTest
@testable import VoxCore

final class TranscriptionModeTests: XCTestCase {
    func testProsePromptRequiresLiteralNonInterpretiveTranscription() {
        let prompt = TranscriptionMode.prose.whisperPrompt.lowercased()

        XCTAssertTrue(prompt.contains("only words supported by the audio"))
        XCTAssertTrue(prompt.contains("do not infer unstated facts"))
        XCTAssertTrue(prompt.contains("answer a question"))
        XCTAssertFalse(prompt.contains("break independent clauses"))
        XCTAssertFalse(prompt.contains("always use digits"))
    }
}
