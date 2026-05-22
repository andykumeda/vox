import Carbon.HIToolbox
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

    func testRemoteTargetsUsePhysicalTypingFallback() {
        XCTAssertTrue(TextInjector.usesPhysicalTypingFallback(for: .screenSharing))
        XCTAssertTrue(TextInjector.usesPhysicalTypingFallback(for: .rustDesk))
        XCTAssertFalse(TextInjector.usesPhysicalTypingFallback(for: .standard))
    }

    func testRemotePhysicalTypingUsesCapsLockForUppercaseRuns() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "AB c",
            mode: .capsLockForUppercase
        )

        XCTAssertEqual(strokes.map(\.code), [
            CGKeyCode(kVK_CapsLock),
            CGKeyCode(kVK_ANSI_A),
            CGKeyCode(kVK_ANSI_B),
            CGKeyCode(kVK_Space),
            CGKeyCode(kVK_CapsLock),
            CGKeyCode(kVK_ANSI_C)
        ])
        XCTAssertTrue(strokes.allSatisfy(\.flags.isEmpty))
    }

    func testCapsLockPhysicalTypingPreservesInitiallyActiveCapsLock() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "aB",
            mode: .capsLockForUppercase,
            initialCapsLockActive: true
        )

        XCTAssertEqual(strokes.map(\.code), [
            CGKeyCode(kVK_CapsLock),
            CGKeyCode(kVK_ANSI_A),
            CGKeyCode(kVK_CapsLock),
            CGKeyCode(kVK_ANSI_B)
        ])
        XCTAssertTrue(strokes.allSatisfy(\.flags.isEmpty))
    }

    func testCapsLockPhysicalTypingClosesAtEndOfUppercaseRun() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "A",
            mode: .capsLockForUppercase
        )

        XCTAssertEqual(strokes.map(\.code), [
            CGKeyCode(kVK_CapsLock),
            CGKeyCode(kVK_ANSI_A),
            CGKeyCode(kVK_CapsLock)
        ])
        XCTAssertTrue(strokes.allSatisfy(\.flags.isEmpty))
    }

    func testRustDeskPhysicalTypingAvoidsShiftModifiers() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "A!",
            mode: .unmodifiedOnly
        )

        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(strokes[0].code, CGKeyCode(kVK_ANSI_A))
        XCTAssertFalse(strokes[0].flags.contains(.maskShift))
        XCTAssertEqual(strokes[1].code, CGKeyCode(kVK_ANSI_Period))
        XCTAssertFalse(strokes[1].flags.contains(.maskShift))
    }
}
