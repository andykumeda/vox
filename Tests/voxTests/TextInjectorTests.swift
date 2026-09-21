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

    func testRustDeskUsesDedicatedRemotePasteTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.carriez.rustdesk",
                localizedName: "RustDesk"
            ),
            .rustDesk
        )
    }

    func testParsecBundleUsesRemotePasteTarget() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "tv.parsec.www",
                localizedName: "Parsec"
            ),
            .parsec
        )
    }

    func testParsecNameUsesRemotePasteTargetWhenBundleDiffers() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.example.remote-client",
                localizedName: "Parsec"
            ),
            .parsec
        )
    }

    func testRemoteControlModeOverridesLocalAppsOnly() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit",
                remoteControlModeEnabled: true
            ),
            .remoteControl
        )
    }

    func testRemoteControlModeDoesNotOverrideRemoteViewers() {
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.carriez.rustdesk",
                localizedName: "RustDesk",
                remoteControlModeEnabled: true
            ),
            .rustDesk
        )
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "com.apple.ScreenSharing",
                localizedName: "Screen Sharing",
                remoteControlModeEnabled: true
            ),
            .screenSharing
        )
        XCTAssertEqual(
            TextInjector.pasteTarget(
                bundleIdentifier: "tv.parsec.www",
                localizedName: "Parsec",
                remoteControlModeEnabled: true
            ),
            .parsec
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

    func testRemoteControlModeDoesNotRestorePreviousClipboardWhenKeepOff() {
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: false,
            target: .remoteControl
        ))
    }

    func testParsecDoesNotRestorePreviousClipboardWhenKeepOff() {
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(
            keepOnClipboard: false,
            target: .parsec
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

    func testRemoteClipboardPasteWaitsForClipboardSync() {
        XCTAssertEqual(TextInjector.prePasteDelay(for: .screenSharing), 2.5)
        XCTAssertEqual(TextInjector.prePasteDelay(for: .rustDesk), 1.25)
        XCTAssertEqual(TextInjector.prePasteDelay(for: .parsec), 1.25)
        XCTAssertEqual(TextInjector.prePasteDelay(for: .remoteControl), 0)
        XCTAssertEqual(TextInjector.prePasteDelay(for: .standard), 0)
    }

    func testScreenSharingContinuesWhenClipboardPushFails() {
        XCTAssertTrue(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .screenSharing))
        XCTAssertFalse(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .rustDesk))
        XCTAssertFalse(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .parsec))
        XCTAssertFalse(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .remoteControl))
        XCTAssertFalse(TextInjector.continuesPasteWhenRemoteClipboardPushFails(for: .standard))
    }

    func testAppleScriptKeystrokeChunksSplitNewlinesAndTabs() {
        XCTAssertEqual(
            TextInjector.appleScriptKeystrokeChunks(for: "A\nB\tC"),
            ["A", "\n", "B", "\t", "C"]
        )
    }

    func testAppleScriptKeystrokeChunksNormalizeCarriageReturns() {
        XCTAssertEqual(
            TextInjector.appleScriptKeystrokeChunks(for: "A\rB\r\nC"),
            ["A", "\n", "B", "\n", "C"]
        )
    }

    func testAppleScriptKeystrokeChunksUseConservativeRemoteChunkSize() {
        let input = String(repeating: "a", count: TextInjector.systemEventsTextChunkLimit + 1)

        XCTAssertEqual(
            TextInjector.appleScriptKeystrokeChunks(for: input),
            [
                String(repeating: "a", count: TextInjector.systemEventsTextChunkLimit),
                "a"
            ]
        )
        XCTAssertGreaterThanOrEqual(TextInjector.systemEventsTextChunkDelay, 0.04)
    }

    func testAppleScriptStringLiteralEscapesQuotesAndBackslashes() {
        XCTAssertEqual(
            TextInjector.appleScriptStringLiteral(#"say "hi" \ ok"#),
            #""say \"hi\" \\ ok""#
        )
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
        XCTAssertEqual(
            TextInjector.textForPaste("does parsec work?", target: .parsec),
            "Does parsec work?"
        )
        XCTAssertEqual(
            TextInjector.textForPaste("what now?", target: .remoteControl),
            "What now?"
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

    func testRemotePhysicalFallbackUsesUnicodeBackedShiftedCharacters() {
        XCTAssertEqual(
            TextInjector.physicalTypingFallbackMode(for: .screenSharing),
            .unicodeBackedShiftedCharacters
        )
        XCTAssertEqual(
            TextInjector.physicalTypingFallbackMode(for: .rustDesk),
            .unicodeBackedShiftedCharacters
        )
        XCTAssertEqual(
            TextInjector.physicalTypingFallbackMode(for: .parsec),
            .unicodeBackedShiftedCharacters
        )
        XCTAssertEqual(
            TextInjector.physicalTypingFallbackMode(for: .remoteControl),
            .withShiftModifiers
        )
    }

    func testAppleScriptProcessSpecifierUsesUnixId() {
        XCTAssertEqual(
            TextInjector.appleScriptProcessSpecifier(processID: 42_424),
            "(first process whose unix id is 42424)"
        )
    }

    func testScreenSharingPhysicalTypingUsesUnicodeBackedShiftedCharacters() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "Hello?",
            mode: .unicodeBackedShiftedCharacters
        )

        XCTAssertEqual(strokes.first?.code, CGKeyCode(kVK_ANSI_H))
        XCTAssertFalse(strokes.first?.flags.contains(.maskShift) == true)
        XCTAssertEqual(strokes.first?.unicodeOverride, "H")
        XCTAssertNil(strokes[1].unicodeOverride)
        XCTAssertEqual(strokes.last?.code, CGKeyCode(kVK_ANSI_Slash))
        XCTAssertFalse(strokes.last?.flags.contains(.maskShift) == true)
        XCTAssertEqual(strokes.last?.unicodeOverride, "?")
    }

    func testShiftModifierPhysicalTypingStillUsesExplicitShift() {
        let strokes = TextInjector.physicalKeystrokes(
            for: "H?",
            mode: .withShiftModifiers
        )

        XCTAssertTrue(strokes[0].flags.contains(.maskShift))
        XCTAssertNil(strokes[0].unicodeOverride)
        XCTAssertTrue(strokes[1].flags.contains(.maskShift))
        XCTAssertNil(strokes[1].unicodeOverride)
    }

    func testUnmodifiedPhysicalTypingFallbackApproximatesShiftedCharacters() {
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
