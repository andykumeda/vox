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
        let result = await proc.process("First. Scratch that. Second.")
        XCTAssertEqual(capture.input, "Second.")
        XCTAssertEqual(result, "[cleaned] Second.")
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
}
