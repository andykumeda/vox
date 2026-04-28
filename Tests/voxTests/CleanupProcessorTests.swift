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

    func testScratchThatTolerantOfTrailingComma() async {
        let proc = makeProseProc()
        let result = await proc.process("Hello. Scratch that, Goodbye.")
        XCTAssertEqual(result, "Goodbye.")
    }
}
