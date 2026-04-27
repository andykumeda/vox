import XCTest
@testable import vox

final class DictionaryMatcherTests: XCTestCase {

    private func entry(
        _ spoken: String, _ replacement: String,
        mode: Scope = .command, startsWith: Bool = false,
        caseInsensitive: Bool = true, enabled: Bool = true
    ) -> DictionaryEntry {
        DictionaryEntry(
            id: "test-\(UUID().uuidString)",
            spoken: spoken, replacement: replacement,
            mode: mode, startsWith: startsWith,
            caseInsensitive: caseInsensitive, enabled: enabled
        )
    }

    func testReplacesSingleTokenMatch() {
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l")],
            to: "ls -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -l")
    }

    func testDoesNotMatchInsideLongerToken() {
        // "-shell" must not match inside "--shell".
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l")],
            to: "usermod --shell /bin/zsh",
            scope: .command
        )
        XCTAssertEqual(result, "usermod --shell /bin/zsh")
    }

    func testStartsWithAnchorsAtTokenZero() {
        let result = DictionaryMatcher.apply(
            entries: [entry("hello,", "ls", startsWith: true)],
            to: "hello, -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -shell")
    }

    func testStartsWithDoesNotMatchMidString() {
        let result = DictionaryMatcher.apply(
            entries: [entry("hello,", "ls", startsWith: true)],
            to: "echo hello, world",
            scope: .command
        )
        XCTAssertEqual(result, "echo hello, world")
    }

    func testCaseInsensitiveByDefault() {
        let result = DictionaryMatcher.apply(
            entries: [entry("vox", "Vox", mode: .prose)],
            to: "running VOX today",
            scope: .prose
        )
        XCTAssertEqual(result, "running Vox today")
    }

    func testCaseSensitiveWhenFlagOff() {
        let result = DictionaryMatcher.apply(
            entries: [entry("vox", "Vox", mode: .prose, caseInsensitive: false)],
            to: "running VOX today",
            scope: .prose
        )
        XCTAssertEqual(result, "running VOX today")
    }

    func testScopeCommandSkipsProseEntries() {
        let result = DictionaryMatcher.apply(
            entries: [entry("vox", "Vox", mode: .prose)],
            to: "vox status",
            scope: .command
        )
        XCTAssertEqual(result, "vox status")
    }

    func testScopeBothFiresInBothModes() {
        let e = entry("foo", "bar", mode: .both)
        XCTAssertEqual(
            DictionaryMatcher.apply(entries: [e], to: "foo", scope: .command),
            "bar"
        )
        XCTAssertEqual(
            DictionaryMatcher.apply(entries: [e], to: "foo", scope: .prose),
            "bar"
        )
    }

    func testDisabledEntryIsNoOp() {
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l", enabled: false)],
            to: "ls -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -shell")
    }

    func testMultiTokenSpoken() {
        let result = DictionaryMatcher.apply(
            entries: [entry("my email", "andy@kumeda.com", mode: .prose)],
            to: "send my email to him",
            scope: .prose
        )
        XCTAssertEqual(result, "send andy@kumeda.com to him")
    }

    func testEmptyReplacementDeletesTokens() {
        let result = DictionaryMatcher.apply(
            entries: [entry("um", "")],
            to: "ls um now",
            scope: .command
        )
        XCTAssertEqual(result, "ls now")
    }

    func testEmptyReplacementAtStart() {
        let result = DictionaryMatcher.apply(
            entries: [entry("um", "", startsWith: true)],
            to: "um ls now",
            scope: .command
        )
        XCTAssertEqual(result, "ls now")
    }

    func testEmptyReplacementAtEnd() {
        let result = DictionaryMatcher.apply(
            entries: [entry("now", "")],
            to: "ls now",
            scope: .command
        )
        XCTAssertEqual(result, "ls")
    }

    func testLongerSpokenWinsOverShorter() {
        // "double dash" (2 tokens) should win over "dash" (1 token) when both
        // could match overlapping windows.
        let entries = [
            entry("dash", "-", mode: .both),
            entry("double dash", "--", mode: .both),
        ]
        let result = DictionaryMatcher.apply(
            entries: entries,
            to: "ls double dash all",
            scope: .command
        )
        XCTAssertEqual(result, "ls -- all")
    }

    func testMultipleNonOverlappingMatchesInOnePass() {
        let result = DictionaryMatcher.apply(
            entries: [entry("-shell", "-l")],
            to: "ls -shell -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -l -l")
    }

    func testEmptyInputReturnsEmpty() {
        let result = DictionaryMatcher.apply(
            entries: [entry("foo", "bar")],
            to: "",
            scope: .command
        )
        XCTAssertEqual(result, "")
    }

    func testNoEntriesIsNoOp() {
        let result = DictionaryMatcher.apply(
            entries: [],
            to: "ls -shell",
            scope: .command
        )
        XCTAssertEqual(result, "ls -shell")
    }
}
