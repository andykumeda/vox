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

    func testScreenSharingNameUsesRemotePasteTargetWhenBundleDiffers() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.apple.ScreenSharingClient",
                localizedName: "Screen Sharing"
            ),
            .screenSharing
        )
    }

    func testScreenSharingBundleVariantUsesRemotePasteTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.apple.screensharing.agent",
                localizedName: "Remote Session"
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

    func testRustDeskDoesNotRestorePreviousClipboardWhenKeepOff() {
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: false,
            target: .rustDesk
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
        XCTAssertFalse(TextInjector.usesPhysicalTypingFallback(for: .screenSharing))
        XCTAssertTrue(TextInjector.usesPhysicalTypingFallback(for: .rustDesk))
        XCTAssertFalse(TextInjector.usesPhysicalTypingFallback(for: .standard))
    }

    func testScreenSharingRequiresExactPaste() {
        XCTAssertTrue(TextInjector.requiresExactPaste(for: .screenSharing))
        XCTAssertFalse(TextInjector.requiresExactPaste(for: .rustDesk))
        XCTAssertFalse(TextInjector.requiresExactPaste(for: .standard))
    }

    func testScreenSharingUsesMenuPasteFallback() {
        XCTAssertTrue(TextInjector.usesMenuPasteFallback(for: .screenSharing))
        XCTAssertFalse(TextInjector.usesMenuPasteFallback(for: .rustDesk))
        XCTAssertFalse(TextInjector.usesMenuPasteFallback(for: .standard))
    }

    func testScreenSharingPasteWaitsForClipboardSync() {
        XCTAssertEqual(TextInjector.prePasteDelay(for: .screenSharing), 3.0)
        XCTAssertEqual(TextInjector.prePasteDelay(for: .rustDesk), 0)
        XCTAssertEqual(TextInjector.prePasteDelay(for: .standard), 0)
    }

    func testScreenSharingPushesSharedClipboardAfterPasteboardWrite() {
        XCTAssertTrue(TextInjector.pushesRemoteClipboardAfterPasteboardWrite(for: .screenSharing))
        XCTAssertFalse(TextInjector.pushesRemoteClipboardAfterPasteboardWrite(for: .rustDesk))
        XCTAssertFalse(TextInjector.pushesRemoteClipboardAfterPasteboardWrite(for: .standard))
    }

    func testScreenSharingContinuesPasteWhenClipboardPushFails() {
        XCTAssertTrue(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .screenSharing))
        XCTAssertFalse(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .rustDesk))
        XCTAssertFalse(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .standard))
    }

    func testRemotePasteCapitalizesProseFirstLetter() {
        XCTAssertEqual(
            TextInjector.textForPaste("hello there.", target: .screenSharing),
            "Hello there."
        )
        XCTAssertEqual(
            TextInjector.textForPaste("  hello there?", target: .rustDesk),
            "  Hello there?"
        )
    }

    func testRemotePasteDoesNotCapitalizeCommandLikeText() {
        XCTAssertEqual(
            TextInjector.textForPaste("git status", target: .screenSharing),
            "git status"
        )
        XCTAssertEqual(
            TextInjector.textForPaste("./scripts/make-dmg.sh", target: .screenSharing),
            "./scripts/make-dmg.sh"
        )
    }

    func testStandardPasteDoesNotRewriteText() {
        XCTAssertEqual(
            TextInjector.textForPaste("hello there.", target: .standard),
            "hello there."
        )
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

    func testCapsLockPhysicalTypingApproximatesQuestionMarkWithoutShift() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "Is it ready?",
            mode: .capsLockForUppercase
        )

        XCTAssertEqual(strokes.last?.code, CGKeyCode(kVK_ANSI_Period))
        XCTAssertFalse(strokes.last?.flags.contains(.maskShift) == true)
    }

    func testCapsLockPhysicalTypingApproximatesQuestionMarkAfterUppercaseRun() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "A?",
            mode: .capsLockForUppercase
        )

        XCTAssertEqual(strokes.map(\.code), [
            CGKeyCode(kVK_CapsLock),
            CGKeyCode(kVK_ANSI_A),
            CGKeyCode(kVK_ANSI_Period),
            CGKeyCode(kVK_CapsLock)
        ])
        XCTAssertFalse(strokes[2].flags.contains(.maskShift))
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
