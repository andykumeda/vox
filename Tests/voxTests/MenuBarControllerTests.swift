import XCTest
@testable import vox

final class MenuBarControllerTests: XCTestCase {
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
