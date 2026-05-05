import XCTest
@testable import vox

final class CleanupProcessorTests: XCTestCase {

    // MARK: - Toggle off

    func testToggleOffReturnsInputUnchanged() async {
        let proc = CleanupProcessor(mode: .prose, enabled: false, llmCleaner: nil)
        let result = await proc.process("Send to Marcus. Scratch that. Send to Lena.")
        XCTAssertEqual(result, "Send to Marcus. Scratch that. Send to Lena.")
    }

    func testToggleOffNeverInvokesLLMCleaner() async {
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return ""
        }
        let proc = CleanupProcessor(mode: .prose, enabled: false, llmCleaner: cleaner)
        _ = await proc.process("Anything at all.")
        XCTAssertFalse(flag.value, "llmCleaner must not be invoked when enabled is false")
    }

    // MARK: - Trigger: scratch that / delete that

    private func makeProseProc() -> CleanupProcessor {
        CleanupProcessor(mode: .prose, enabled: true, llmCleaner: { $0 })
    }

    func testScratchThatWipesPrecedingSentence() async {
        let proc = makeProseProc()
        let result = await proc.process("Send to Marcus. Scratch that. Send to Lena.")
        XCTAssertEqual(result, "Send to Lena.")
    }

    func testDeleteThatWipesPrecedingSentence() async {
        let proc = makeProseProc()
        let result = await proc.process("First. Second. Delete that.")
        XCTAssertEqual(result, "First.")
    }

    func testScratchThatAtStartReturnsEmpty() async {
        let proc = makeProseProc()
        let result = await proc.process("Scratch that.")
        XCTAssertEqual(result, "")
    }

    func testScratchThatCaseInsensitive() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello there. SCRATCH THAT. Goodbye.")
        XCTAssertEqual(result, "Goodbye.")
    }

    // Known limitation: comma-joined triggers (e.g., "Scratch that, Goodbye.") are
    // not detected because the macOS sentence tokenizer keeps them as one sentence
    // and our trigger regex requires the trigger to BE the full sentence. The LLM
    // cleanup pass (prose mode only) handles these cases instead. Documented here
    // so it doesn't get re-introduced as a "bug" in future review.
    func testScratchThatCommaJoinedIsKnownLimitation() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello. Scratch that, Goodbye.")
        XCTAssertEqual(result, "Hello. Scratch that, Goodbye.",
                       "When trigger is comma-joined to next clause, it is left in place; LLM handles it in prose.")
    }

    // MARK: - Trigger: new paragraph

    func testNewParagraphInsertsDoubleNewline() async {
        let proc = makeProseProc()
        let result = await proc.process("Para one. New paragraph. Para two.")
        XCTAssertEqual(result, "Para one.\n\nPara two.")
    }

    func testNewParagraphCaseInsensitive() async {
        let proc = makeProseProc()
        let result = await proc.process("Header. NEW PARAGRAPH. Body.")
        XCTAssertEqual(result, "Header.\n\nBody.")
    }

    func testNewParagraphMultipleInOneUtterance() async {
        let proc = makeProseProc()
        let result = await proc.process("First. New paragraph. Second. New paragraph. Third.")
        XCTAssertEqual(result, "First.\n\nSecond.\n\nThird.")
    }

    // MARK: - Trigger: new line

    func testNewLineInsertsSingleNewline() async {
        let proc = makeProseProc()
        let result = await proc.process("Item one. New line. Item two.")
        XCTAssertEqual(result, "Item one.\nItem two.")
    }

    func testNewLineCaseInsensitive() async {
        let proc = makeProseProc()
        let result = await proc.process("Alpha. NEW LINE. Beta.")
        XCTAssertEqual(result, "Alpha.\nBeta.")
    }

    // MARK: - Trigger false positives

    func testScratchThatItchDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "I want to scratch that itch."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    func testNewParagraphFormatDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "We need a new paragraph format for this document."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    func testNewLineOfCodeDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "Add a new line of code to the function."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    func testDeleteThatBugDoesNotTrigger() async {
        let proc = makeProseProc()
        let input = "We should delete that bug from the queue."
        let result = await proc.process(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - Trigger punctuation tolerance

    func testScratchThatExclamationWipesPrecedingSentence() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello. Scratch that! Goodbye.")
        XCTAssertEqual(result, "Goodbye.")
    }

    func testScratchThatQuestionWipesPrecedingSentence() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello. Scratch that? Goodbye.")
        XCTAssertEqual(result, "Goodbye.")
    }

    // MARK: - Orchestrator

    func testProseInvokesLLMWithTriggeredText() async {
        final class Capture { var input: String? }
        let capture = Capture()
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            capture.input = input
            return "[cleaned] \(input)"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        // Triggered text must be at least 15 chars to survive the short-input
        // bypass and reach the LLM.
        let result = await proc.process("First sentence here. Scratch that. Second sentence here for real.")
        XCTAssertEqual(capture.input, "Second sentence here for real.")
        XCTAssertEqual(result, "[cleaned] Second sentence here for real.")
    }

    // MARK: - Short-input bypass

    func testProseShortInputSkipsLLM() async {
        // gpt-4o-mini sometimes treats short snippets as chat requests; bypass
        // the LLM entirely for inputs under 15 chars (after triggers).
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "should not be used"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Okay.")
        XCTAssertFalse(flag.value, "LLM must NOT be invoked for short inputs")
        XCTAssertEqual(result, "Okay.")
    }

    func testProseLongerInputStillInvokesLLM() async {
        // Sanity check that the short-input bypass doesn't suppress real-length
        // dictations.
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            flag.value = true
            return input
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        _ = await proc.process("This is a longer dictation that should reach the LLM.")
        XCTAssertTrue(flag.value)
    }

    func testCommandModeSkipsLLM() async {
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "should not be used"
        }
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Open the file. Scratch that. Close the file.")
        XCTAssertFalse(flag.value)
        XCTAssertEqual(result, "Close the file.")
    }

    func testEmptyInputSkipsLLM() async {
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "noop"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("")
        XCTAssertFalse(flag.value)
        XCTAssertEqual(result, "")
    }

    func testWhitespaceOnlyInputSkipsLLM() async {
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "noop"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("   \n  ")
        XCTAssertFalse(flag.value)
        XCTAssertEqual(result, "")
    }

    func testNoLLMInjectedSkipsLLM() async {
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: nil)
        let result = await proc.process("Hello world.")
        XCTAssertEqual(result, "Hello world.")
    }

    // MARK: - Fail-open

    func testLLMThrowsReturnsTriggeredText() async {
        struct DummyError: Error {}
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in throw DummyError() }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Hello. Scratch that. World.")
        XCTAssertEqual(result, "World.")
    }

    func testLLMHTTPErrorReturnsTriggeredText() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            throw NSError(domain: "test", code: 500, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Goodbye world.")
        XCTAssertEqual(result, "Goodbye world.")
    }

    // MARK: - Small-output guard

    func testLLMEmptyOutputReturnsTriggeredText() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in return "" }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Hey there friend, how are you doing?")
        XCTAssertEqual(result, "Hey there friend, how are you doing?")
    }

    func testLLMTinyOutputReturnsTriggeredText() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in return "." }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("This is a complete sentence with several words.")
        XCTAssertEqual(result, "This is a complete sentence with several words.")
    }

    func testLLMShortInputAllowsShortOutput() async {
        // If input is short, a short output is fine — guard only kicks in when input is long.
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in return "Hi." }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Hi.")
        XCTAssertEqual(result, "Hi.")
    }

    // MARK: - Command mode triggers (substring-based, tolerant of missing punct)

    func testCommandModeTriggerWithoutPunctuation() async {
        // Whisper command-mode prompt forbids trailing punctuation, so input
        // is often one continuous sentence. Trigger must still fire.
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: nil)
        let result = await proc.process("open the file scratch that close the file")
        XCTAssertEqual(result, "close the file")
    }

    func testCommandModeMultipleTriggersKeepLast() async {
        // Multiple "scratch that" — keep only what's after the last one.
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: nil)
        let result = await proc.process("ls scratch that grep foo scratch that wc -l")
        XCTAssertEqual(result, "wc -l")
    }

    func testCommandModeTriggerWithPeriodStillWorks() async {
        // Existing test case: with punctuation, command mode also works.
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: nil)
        let result = await proc.process("Open the file. Scratch that. Close the file.")
        XCTAssertEqual(result, "Close the file.")
    }

    func testCommandModeNoTriggerLeavesUnchanged() async {
        // No trigger: input passes through unchanged.
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: nil)
        let result = await proc.process("ls -la")
        XCTAssertEqual(result, "ls -la")
    }

    func testCommandModeNewParagraphSubstring() async {
        // "new paragraph" works as substring in command mode (e.g., for echo
        // or vim heredoc dictation).
        let proc = CleanupProcessor(mode: .command, enabled: true, llmCleaner: nil)
        let result = await proc.process("first line new paragraph second line")
        XCTAssertEqual(result, "first line\n\nsecond line")
    }

    // MARK: - Newline-bypass: paragraph triggers skip the LLM entirely

    func testProseParagraphTriggerSkipsLLMEntirely() async {
        // gpt-4o-mini cannot be relied on to preserve placeholder tokens; the
        // safest behavior is to bypass the LLM whenever the triggered text
        // contains an explicit \n or \n\n. Verify the cleaner closure is
        // never invoked in that case.
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "should not be used"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("First. New paragraph. Second.")
        XCTAssertFalse(flag.value, "LLM must NOT be invoked when triggered text contains newlines")
        XCTAssertEqual(result, "First.\n\nSecond.")
    }

    func testProseNewLineTriggerSkipsLLMEntirely() async {
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "should not be used"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Item one. New line. Item two.")
        XCTAssertFalse(flag.value)
        XCTAssertEqual(result, "Item one.\nItem two.")
    }

    func testVerbatimPrefixSkipsTriggersAndLLM() async {
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in
            flag.value = true
            return "should not be used"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Verbatim, um he literally said scratch that um yeah okay.")
        XCTAssertFalse(flag.value, "Verbatim prefix must skip the LLM cleaner")
        XCTAssertEqual(result, "um he literally said scratch that um yeah okay.")
    }

    func testLiteralPrefixSkipsCleanup() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in "should not be used" }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("Literal: he said um maybe.")
        XCTAssertEqual(result, "he said um maybe.")
    }

    func testVerbatimPrefixCaseInsensitive() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { _ in "wrong" }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("VERBATIM the quick brown fox.")
        XCTAssertEqual(result, "the quick brown fox.")
    }

    func testVerbatimMidSentenceNotStripped() async {
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in "[cleaned] \(input)" }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("I want a verbatim quote here.")
        XCTAssertEqual(result, "[cleaned] I want a verbatim quote here.")
    }

    func testProseNoNewlinesStillInvokesLLM() async {
        // Sanity: when triggered text has no newlines, the LLM is still called.
        final class FlagBox { var value = false }
        let flag = FlagBox()
        let cleaner: CleanupProcessor.LLMCleanFunc = { input in
            flag.value = true
            return "[cleaned] \(input)"
        }
        let proc = CleanupProcessor(mode: .prose, enabled: true, llmCleaner: cleaner)
        let result = await proc.process("This is plain prose with no triggers.")
        XCTAssertTrue(flag.value, "LLM must be invoked when triggered text has no newlines")
        XCTAssertEqual(result, "[cleaned] This is plain prose with no triggers.")
    }
}
