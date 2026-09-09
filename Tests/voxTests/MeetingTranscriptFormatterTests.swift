import XCTest
@testable import vox
@testable import VoxCore

final class MeetingTranscriptFormatterTests: XCTestCase {
    func testPlainTextGroupsConsecutiveSegmentsBySpeaker() {
        let session = makeSession(segments: [
            TranscriptSegment(startTime: 0, endTime: 2, text: "First thought.", source: .local),
            TranscriptSegment(startTime: 2, endTime: 4, text: "More detail.", source: .local),
            TranscriptSegment(startTime: 4, endTime: 6, text: "Response.", source: .remote),
        ])

        XCTAssertEqual(
            MeetingTranscriptFormatter.render(session, format: .plain),
            "You: First thought. More detail.\n\nOther: Response."
        )
    }

    func testTimestampedTextUsesDiarizedSpeakerLabelsAndHourFormat() {
        let session = makeSession(segments: [
            TranscriptSegment(
                startTime: 3_661, endTime: 3_663,
                text: "After an hour.", source: .remote, speakerID: 2
            ),
        ])

        XCTAssertEqual(
            MeetingTranscriptFormatter.render(session, format: .timestamped),
            "[1:01:01] Speaker 2: After an hour."
        )
    }

    private func makeSession(segments: [TranscriptSegment]) -> TranscriptSession {
        TranscriptSession(
            id: UUID(),
            title: "Test Meeting",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            status: .completed,
            chunksTotal: 1,
            chunksCompleted: 1,
            segments: segments,
            audioRetained: false
        )
    }
}
