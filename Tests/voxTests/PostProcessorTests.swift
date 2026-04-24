import XCTest
@testable import vox

final class PostProcessorTests: XCTestCase {

    // MARK: - Prose mode

    func testProseAddsSpaceAfterPeriod() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello.how are you"), "Hello. How are you. ")
    }

    func testProseCapitalizesFirstLetter() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello world"), "Hello world. ")
    }

    func testProseCapitalizesAfterPeriod() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello. how are you"), "Hello. How are you. ")
    }

    func testProseConvertsNumbers() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("i have twenty three apples"), "I have 23 apples. ")
    }

    func testProseMultiSentenceCombined() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(
            p.apply("hello world. this is a test. i have twenty three apples"),
            "Hello world. This is a test. I have 23 apples. "
        )
    }

    func testProseCollapsesWhitespace() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("  hello    world  "), "Hello world. ")
    }

    func testProseHandlesQuestionMark() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("really?yes"), "Really? Yes. ")
    }

    func testProsePreservesExistingTerminalPunctuation() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("already ends properly."), "Already ends properly. ")
    }

    func testProsePreservesExistingQuestionMark() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("how are you?"), "How are you? ")
    }

    // MARK: - Command mode

    func testCommandLowercasesFirstLetter() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("Sudo apt update"), "sudo apt update")
    }

    func testCommandStripsTrailingPeriod() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("sudo apt update."), "sudo apt update")
    }

    func testCommandStripsMultipleTrailingPunct() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls -la."), "ls -la")
    }

    func testCommandDoesNotCapitalizeAfterPeriod() {
        let p = PostProcessor(mode: .command)
        let result = p.apply("grep foo. bar")
        XCTAssertFalse(result.contains(" B"))
    }

    func testCommandNormalizesNumbersToo() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("head -n twenty"), "head -n 20")
    }

    func testCommandPreservesFlags() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls --all -la"), "ls --all -la")
    }

    func testCommandHasNoTrailingSpace() {
        let p = PostProcessor(mode: .command)
        let result = p.apply("ls -la")
        XCTAssertFalse(result.hasSuffix(" "))
    }
}
