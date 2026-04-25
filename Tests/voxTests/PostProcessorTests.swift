import XCTest
@testable import vox

final class PostProcessorTests: XCTestCase {

    // MARK: - Prose mode

    func testProseAddsSpaceAfterPeriod() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello.how are you"), "Hello. How are you?")
    }

    func testProseCapitalizesFirstLetter() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello world"), "Hello world.")
    }

    func testProseCapitalizesAfterPeriod() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello. how are you"), "Hello. How are you?")
    }

    func testProseConvertsCompoundNumbers() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("i have twenty three apples"), "I have 23 apples.")
    }

    func testProseLeavesSingleDigitWordAsWord() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("i have three apples"), "I have three apples.")
    }

    func testProseMultiSentenceCombined() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(
            p.apply("hello world. this is a test. i have twenty three apples"),
            "Hello world. This is a test. I have 23 apples."
        )
    }

    // MARK: - URL / domain / filename shielding

    func testProsePreservesBareDomain() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("check out youtube.com"), "Check out youtube.com.")
    }

    func testProsePreservesURLWithPath() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(
            p.apply("see https://github.com/user/repo for details"),
            "See https://github.com/user/repo for details."
        )
    }

    func testProsePreservesIPAddress() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("ping 192.168.1.1"), "Ping 192.168.1.1.")
    }

    func testProsePreservesFilename() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("open README.md"), "Open README.md.")
    }

    func testProseStillAddsSpaceForRegularSentenceEnd() {
        // Shielding must not leak into normal sentence boundaries.
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("hello.how are you"), "Hello. How are you?")
    }

    func testProseCollapsesWhitespace() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("  hello    world  "), "Hello world.")
    }

    func testProseHandlesQuestionMark() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("really?yes"), "Really? Yes.")
    }

    func testProsePreservesExistingTerminalPunctuation() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("already ends properly."), "Already ends properly.")
    }

    func testProsePreservesExistingQuestionMark() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("how are you?"), "How are you?")
    }

    func testProseAddsQuestionMarkForQuestionWord() {
        // "Is" starts a question — terminator should be "?" not ".".
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("is it raining"), "Is it raining?")
    }

    func testProseAddsQuestionMarkForWhWord() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("why did you do that"), "Why did you do that?")
    }

    func testProseStillPeriodForStatement() {
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(p.apply("the sky is blue"), "The sky is blue.")
    }

    func testProseQuestionDetectionForFinalSentenceOnly() {
        // First sentence is a statement, second is a question — only second
        // gets "?" appended.
        let p = PostProcessor(mode: .prose)
        XCTAssertEqual(
            p.apply("hello world. is it raining"),
            "Hello world. Is it raining?"
        )
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

    func testCommandNormalizesBareSingleDigit() {
        // In command mode, single small numbers must convert ("head -n 3"),
        // unlike prose where they stay as words.
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("head -n three"), "head -n 3")
    }

    // MARK: - Spoken punctuation (command mode)

    func testCommandDashWordToHyphen() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("head dash n three"), "head -n 3")
    }

    func testCommandDoubleDashToLongFlag() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls double dash all"), "ls --all")
    }

    func testCommandDotWordGluesFilename() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("cat readme dot md"), "cat readme.md")
    }

    func testCommandPipeWordToPipe() {
        // Pipe stays with surrounding spaces — shell tolerates either form.
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls pipe grep foo"), "ls | grep foo")
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

    func testCommandSplitsJoinedFlag() {
        // Whisper sometimes emits "ls-l" without a space — split it.
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls-l"), "ls -l")
    }

    func testCommandSplitsJoinedLongFlag() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("grep-i foo"), "grep -i foo")
    }

    func testCommandLeavesAlreadySpacedCommand() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls -la"), "ls -la")
    }

    func testCommandDoesNotSplitSshKeygen() {
        // "ssh-keygen" is a real binary — must not become "ssh -keygen".
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ssh-keygen -t ed25519"), "ssh-keygen -t ed25519")
    }

    func testCommandDoesNotSplitPathsWithDash() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("cat /tmp/some-file.txt"), "cat /tmp/some-file.txt")
    }

    // MARK: - Trailing key suffix (command mode)

    func testCommandStripsTrailingTab() {
        let p = PostProcessor(mode: .command)
        let r = p.process("brew upd tab")
        XCTAssertEqual(r.text, "brew upd")
        XCTAssertEqual(r.suffixKeys, [.tab])
    }

    func testCommandStripsTrailingReturn() {
        let p = PostProcessor(mode: .command)
        let r = p.process("ls -la return")
        XCTAssertEqual(r.text, "ls -la")
        XCTAssertEqual(r.suffixKeys, [.return])
    }

    func testCommandStripsTrailingEnter() {
        let p = PostProcessor(mode: .command)
        let r = p.process("pwd enter")
        XCTAssertEqual(r.text, "pwd")
        XCTAssertEqual(r.suffixKeys, [.return])
    }

    func testCommandStripsTabThenReturn() {
        let p = PostProcessor(mode: .command)
        let r = p.process("brew upd tab return")
        XCTAssertEqual(r.text, "brew upd")
        XCTAssertEqual(r.suffixKeys, [.tab, .return])
    }

    func testCommandLoneTabStaysAsText() {
        // Single-word "tab" — too risky to interpret, leave as text.
        let p = PostProcessor(mode: .command)
        let r = p.process("tab")
        XCTAssertEqual(r.text, "tab")
        XCTAssertEqual(r.suffixKeys, [])
    }

    func testCommandLoneReturnFiresKey() {
        let p = PostProcessor(mode: .command)
        let r = p.process("return")
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.suffixKeys, [.return])
    }

    func testCommandLoneEnterFiresKey() {
        let p = PostProcessor(mode: .command)
        let r = p.process("enter")
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.suffixKeys, [.return])
    }

    func testCommandLoneEscapeFiresKey() {
        let p = PostProcessor(mode: .command)
        let r = p.process("escape")
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.suffixKeys, [.escape])
    }

    func testCommandNoSuffixWhenAbsent() {
        let p = PostProcessor(mode: .command)
        let r = p.process("ls -la")
        XCTAssertEqual(r.text, "ls -la")
        XCTAssertEqual(r.suffixKeys, [])
    }

    func testProseDoesNotStripTrailingTab() {
        // "tab" suffix logic is command-only. Prose adds a trailing Space key
        // for sentence separation, never Tab.
        let p = PostProcessor(mode: .prose)
        let r = p.process("press tab")
        XCTAssertEqual(r.text, "Press tab.")
        XCTAssertEqual(r.suffixKeys, [.space])
    }

    // MARK: - Control + letter

    func testCommandStandaloneControlC() {
        let p = PostProcessor(mode: .command)
        let r = p.process("control C")
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.suffixKeys, [.control("c")])
    }

    func testCommandCtrlAlias() {
        let p = PostProcessor(mode: .command)
        let r = p.process("ctrl D")
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.suffixKeys, [.control("d")])
    }

    func testCommandTextThenControlC() {
        let p = PostProcessor(mode: .command)
        let r = p.process("ls -la control C")
        XCTAssertEqual(r.text, "ls -la")
        XCTAssertEqual(r.suffixKeys, [.control("c")])
    }

    func testCommandControlThenTab() {
        let p = PostProcessor(mode: .command)
        let r = p.process("ls control C tab")
        XCTAssertEqual(r.text, "ls")
        XCTAssertEqual(r.suffixKeys, [.control("c"), .tab])
    }

    func testCommandSingleLetterCStaysAsText() {
        // Bare "C" without "control" prefix must not be misread as a key.
        let p = PostProcessor(mode: .command)
        let r = p.process("echo C")
        XCTAssertEqual(r.text, "echo C")
        XCTAssertEqual(r.suffixKeys, [])
    }

    // MARK: - Escape

    func testCommandEscape() {
        let p = PostProcessor(mode: .command)
        let r = p.process("vim escape")
        XCTAssertEqual(r.text, "vim")
        XCTAssertEqual(r.suffixKeys, [.escape])
    }

    func testCommandEscAlias() {
        let p = PostProcessor(mode: .command)
        let r = p.process("foo esc")
        XCTAssertEqual(r.text, "foo")
        XCTAssertEqual(r.suffixKeys, [.escape])
    }

    // MARK: - NATO phonetic + minus alias

    func testCommandNatoPhoneticAfterDash() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls dash lima"), "ls -l")
    }

    func testCommandMinusAlias() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("ls minus l"), "ls -l")
    }

    func testCommandMinusPlusNato() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("rm minus romeo foxtrot"), "rm -rf")
    }

    func testCommandNatoOnlyAfterDash() {
        // "echo" alone is the shell command, not NATO 'e'. Don't expand.
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("echo lima"), "echo lima")
    }

    func testCommandDoubleDashLongFlagWithNato() {
        let p = PostProcessor(mode: .command)
        XCTAssertEqual(p.apply("git double dash help"), "git --help")
    }
}
