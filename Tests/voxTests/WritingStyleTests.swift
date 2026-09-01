import Foundation
import XCTest
@testable import vox

final class WritingStyleTests: XCTestCase {
    private var tempDirectory: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-writing-style-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "vox-writing-style-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        if let name = defaults.volatileDomainNames.first(where: { $0.contains("vox-writing-style-tests") }) {
            defaults.removePersistentDomain(forName: name)
        }
    }

    func testLinkedMarkdownIsReadFreshAndReplacesFallback() throws {
        let url = tempDirectory.appendingPathComponent("style.md")
        try "Use short sentences.".write(to: url, atomically: true, encoding: .utf8)
        let store = makeStore()
        try store.select(url)

        XCTAssertEqual(store.activeInstructions(fallback: "fallback"), "Use short sentences.")

        try "Keep my contractions.".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.activeInstructions(fallback: "fallback"), "Keep my contractions.")
    }

    func testMissingLinkedFileFallsBackWithoutDiscardingBookmark() throws {
        let url = tempDirectory.appendingPathComponent("missing.md")
        let store = makeStore()
        try store.select(url)

        XCTAssertEqual(store.activeInstructions(fallback: "inline fallback"), "inline fallback")
        XCTAssertTrue(store.hasLinkedFile)
    }

    func testOversizedStyleFileIsRejected() throws {
        let url = tempDirectory.appendingPathComponent("large.md")
        try Data(repeating: 0x41, count: WritingStyleSourceStore.maximumBytes + 1).write(to: url)
        let store = makeStore()
        try store.select(url)

        XCTAssertThrowsError(try store.loadExternal()) { error in
            XCTAssertEqual(error as? WritingStyleSourceError, .fileTooLarge)
        }
    }

    func testExportIsDeterministicAndContainsNoTranscriptBodies() {
        let entry = DictationEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            mode: "prose",
            durationSec: 2,
            wordCount: 3,
            text: "I'm ready now.",
            rawText: "Um I'm ready now."
        )

        let first = WritingStyleExporter.markdown(dictations: [entry], meetings: [])
        let second = WritingStyleExporter.markdown(dictations: [entry], meetings: [])

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("---\nname: personal-writing-voice\n"))
        XCTAssertTrue(first.contains("## Choose the register before writing"))
        XCTAssertTrue(first.contains("## A practical composition prompt"))
        XCTAssertTrue(first.contains("## Final check"))
        XCTAssertTrue(first.contains("1 of 1 eligible dictations differed"))
        XCTAssertTrue(first.contains("500 prose dictations or 10,000–15,000 attributable words"))
        XCTAssertFalse(first.contains("I'm ready now."))
        XCTAssertFalse(first.contains("Um I'm ready now."))
    }

    func testExportUsesOnlyAttributableMeetingSpeech() {
        let session = TranscriptSession(
            id: UUID(),
            title: "Meeting",
            startedAt: Date(timeIntervalSince1970: 200),
            endedAt: Date(timeIntervalSince1970: 300),
            status: .completed,
            chunksTotal: 1,
            chunksCompleted: 1,
            segments: [
                TranscriptSegment(
                    startTime: 0, endTime: 1,
                    text: "LOCAL_PRIVATE_EXCERPT",
                    source: .local
                ),
                TranscriptSegment(
                    startTime: 1, endTime: 2,
                    text: "REMOTE_PRIVATE_EXCERPT",
                    source: .remote
                ),
            ],
            audioRetained: false
        )

        let result = WritingStyleExporter.markdown(dictations: [], meetings: [session])

        XCTAssertTrue(result.contains("1 explicitly local-speaker meeting segments"))
        XCTAssertTrue(result.contains("1 remote or unattributed meeting segments were excluded"))
        XCTAssertFalse(result.contains("LOCAL_PRIVATE_EXCERPT"))
        XCTAssertFalse(result.contains("REMOTE_PRIVATE_EXCERPT"))
    }

    func testEmptyExportIsStillAnImportableStarterSkill() {
        let result = WritingStyleExporter.markdown(dictations: [], meetings: [])

        XCTAssertTrue(result.hasPrefix("---\nname: personal-writing-voice\n"))
        XCTAssertTrue(result.contains("## Recommended sample size"))
        XCTAssertTrue(result.contains("## Safe starter instruction"))
    }

    func testTranscriptComparisonShowsRawAndFinal() {
        XCTAssertEqual(
            TranscriptComparison.diff(raw: "um hello", final: "Hello."),
            "− Raw: um hello\n+ Final: Hello."
        )
        XCTAssertEqual(TranscriptComparison.diff(raw: "same", final: "same"), "No changes.")
    }

    private func makeStore() -> WritingStyleSourceStore {
        WritingStyleSourceStore(
            defaults: defaults,
            bookmarkKey: "bookmark",
            makeBookmark: { Data($0.path.utf8) },
            resolveBookmark: { data in
                guard let path = String(data: data, encoding: .utf8) else {
                    throw WritingStyleSourceError.invalidBookmark
                }
                return (URL(fileURLWithPath: path), false)
            }
        )
    }
}
