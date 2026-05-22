import XCTest
@testable import vox

final class TextInjectorTests: XCTestCase {
    func testAppleScreenSharingUsesRemotePasteTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.apple.ScreenSharing",
                localizedName: "Screen Sharing"
            ),
            .screenSharing
        )
    }

    func testVNCBundleUsesRemotePasteTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.realvnc.vncviewer",
                localizedName: "RealVNC Viewer"
            ),
            .screenSharing
        )
    }

    func testRustDeskUsesPhysicalTypingTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.carriez.rustdesk",
                localizedName: "RustDesk"
            ),
            .rustDesk
        )
    }

    func testStandardAppUsesStandardPasteTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit"
            ),
            .standard
        )
    }

    func testVNCDoesNotRestorePreviousClipboardWhenKeepOff() {
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: false,
            target: .screenSharing
        ))
    }

    func testStandardPasteRestoresPreviousClipboardWhenKeepOff() {
        XCTAssertTrue(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: false,
            target: .standard
        ))
    }

    func testKeepOnClipboardSuppressesRestoreForAllTargets() {
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: true,
            target: .standard
        ))
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: true,
            target: .screenSharing
        ))
    }
}
