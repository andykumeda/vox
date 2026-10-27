import XCTest
@testable import vox

final class MenuBarControllerTests: XCTestCase {
    func testIdleErrorAndTranscribingStatesAcceptARecordingAttempt() {
        XCTAssertTrue(MenuIconState.idle.acceptsRecordingAttempt)
        XCTAssertTrue(MenuIconState.error.acceptsRecordingAttempt)
        XCTAssertTrue(MenuIconState.transcribing.acceptsRecordingAttempt)
        XCTAssertFalse(MenuIconState.recording.acceptsRecordingAttempt)
        XCTAssertFalse(MenuIconState.starting.acceptsRecordingAttempt)
        XCTAssertEqual(MenuIconState.starting.resolvedAfterPipelineCompletion(remainingPipelines: 0, hadError: false), .starting)
    }

    func testCompletingOlderPipelineDoesNotOverrideNewRecordingState() {
        XCTAssertEqual(
            MenuIconState.recording.resolvedAfterPipelineCompletion(
                remainingPipelines: 0,
                hadError: false
            ),
            .recording
        )
        XCTAssertEqual(
            MenuIconState.transcribing.resolvedAfterPipelineCompletion(
                remainingPipelines: 1,
                hadError: false
            ),
            .transcribing
        )
        XCTAssertEqual(
            MenuIconState.transcribing.resolvedAfterPipelineCompletion(
                remainingPipelines: 0,
                hadError: false
            ),
            .idle
        )
    }

    func testCaptureRestartCannotInterruptDictationOrMeetingWork() {
        XCTAssertTrue(MenuBarController.canRestartCapture(activePipelines: 0, meetingActive: false))
        XCTAssertFalse(MenuBarController.canRestartCapture(activePipelines: 1, meetingActive: false))
        XCTAssertFalse(MenuBarController.canRestartCapture(activePipelines: 0, meetingActive: true))
    }

    func testMenuContainsOnlyRequestedCommandsInOrder() {
        XCTAssertEqual(
            MenuBarCommand.allCases.map(\.title),
            [
                "Dashboard",
                "Meeting",
                "Paste Last Transcription",
                "Settings",
                "Check for Updates…",
                "Help",
                "Quit Vox",
            ]
        )
    }

    func testPasteLastWaitsForMenuAndModifierFocusToSettle() {
        XCTAssertGreaterThanOrEqual(MenuBarController.pasteLastFocusSettleDelay, 0.15)
    }

    func testWarmDictationAPIKeyReadsProviderAndReportsAvailability() {
        var calls = 0
        var logMessage = ""

        let hasKey = MenuBarController.warmDictationAPIKey(
            apiKeyProvider: {
                calls += 1
                return " sk-test "
            },
            log: { logMessage = $0 }
        )

        XCTAssertTrue(hasKey)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(logMessage.contains("dictation api key warmup"))
        XCTAssertTrue(logMessage.contains("has_key=true"))
    }
}
