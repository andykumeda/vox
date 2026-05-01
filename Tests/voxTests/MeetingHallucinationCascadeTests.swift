import XCTest
@testable import vox

/// Unit-level coverage for `collapseRepetitionRuns`, the post-Whisper guard
/// that drops cascades of identical short segments — the symptom we saw on
/// the 2026-05-01 mic stream where Whisper invented "I don't know." once per
/// second across an entire muted 5-minute chunk.
final class MeetingHallucinationCascadeTests: XCTestCase {
    private func seg(_ start: Double, _ end: Double, _ text: String, _ source: SegmentSource = .local) -> TranscriptSegment {
        TranscriptSegment(startTime: start, endTime: end, text: text, source: source)
    }

    func testDropsLongCascade() {
        var segs: [TranscriptSegment] = []
        for i in 0..<200 {
            segs.append(seg(Double(i), Double(i) + 1, "I don't know."))
        }
        let out = MeetingTranscriptionSession.collapseRepetitionRuns(segs, minRun: 4, source: .local)
        XCTAssertEqual(out.count, 0)
    }

    func testKeepsShortRunBelowThreshold() {
        let segs = [
            seg(0, 1, "Yes."),
            seg(1, 2, "Yes."),
            seg(2, 3, "Yes."),
        ]
        // 3 < minRun(4) — keep them.
        let out = MeetingTranscriptionSession.collapseRepetitionRuns(segs, minRun: 4, source: .local)
        XCTAssertEqual(out.count, 3)
    }

    func testKeepsRealConversationInterspersedWithCascade() {
        var segs: [TranscriptSegment] = [
            seg(0, 1, "Scott?", .local),
            seg(1, 2, "Hi.", .local),
            seg(2, 3, "Good morning.", .local),
        ]
        for i in 0..<100 {
            segs.append(seg(Double(3 + i), Double(4 + i), "I don't know.", .local))
        }
        segs.append(seg(104, 105, "Take care.", .local))
        let out = MeetingTranscriptionSession.collapseRepetitionRuns(segs, minRun: 4, source: .local)
        XCTAssertEqual(out.map(\.text), ["Scott?", "Hi.", "Good morning.", "Take care."])
    }

    func testNormalisesPunctuationAndCase() {
        let segs = [
            seg(0, 1, "I don't know."),
            seg(1, 2, "i don't know"),
            seg(2, 3, "I dont know!"),
            seg(3, 4, "I DON'T KNOW?"),
        ]
        let out = MeetingTranscriptionSession.collapseRepetitionRuns(segs, minRun: 4, source: .local)
        XCTAssertEqual(out.count, 0)
    }

    func testEmptyTextRunIsNotDroppedAsCascade() {
        // Whisper sometimes emits empty-text segments; treat those as
        // structural noise, not as a "cascade" worth flagging.
        let segs = [
            seg(0, 0.1, ""),
            seg(0.1, 0.2, ""),
            seg(0.2, 0.3, ""),
            seg(0.3, 0.4, ""),
        ]
        let out = MeetingTranscriptionSession.collapseRepetitionRuns(segs, minRun: 4, source: .local)
        XCTAssertEqual(out.count, 4)
    }
}
