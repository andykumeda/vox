import XCTest
@testable import vox

final class MeetingSummarizerTests: XCTestCase {

    private func segment(_ text: String, source: SegmentSource = .remote, start: Double = 0) -> TranscriptSegment {
        TranscriptSegment(startTime: start, endTime: start + 1, text: text, source: source)
    }

    // MARK: - formatTranscript

    func testFormatTranscriptTagsLocalAndRemote() {
        let segs = [
            segment("Hi everyone.", source: .local, start: 0),
            segment("Hi Andy.", source: .remote, start: 1),
        ]
        let out = MeetingSummarizer.formatTranscript(segs)
        XCTAssertEqual(out, "Local: Hi everyone.\nRemote: Hi Andy.")
    }

    // MARK: - summarize

    func testSummarizeSendsFormattedTranscriptAndReturnsSummary() async throws {
        let segs = [
            segment("Let's plan the launch.", source: .local, start: 0),
            segment("Friday works for me.", source: .remote, start: 1),
        ]
        let expectedMarkdown = "## Summary\nPlanning the launch."
        let mockSend: MeetingSummarizer.HTTPSend = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            // Body must contain the formatted transcript.
            let bodyData = request.httpBody ?? Data()
            let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
            XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
            let messages = body["messages"] as? [[String: Any]] ?? []
            let userContent = messages.last?["content"] as? String ?? ""
            XCTAssertTrue(userContent.contains("Local: Let's plan the launch."))
            XCTAssertTrue(userContent.contains("Remote: Friday works for me."))

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload: [String: Any] = [
                "choices": [["message": ["content": expectedMarkdown]]]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (data, response)
        }
        let summarizer = MeetingSummarizer(
            apiKeyProvider: { "sk-test" },
            send: mockSend
        )
        let result = try await summarizer.summarize(segments: segs)
        XCTAssertEqual(result, expectedMarkdown)
    }

    func testSummarizeThrowsOnMissingAPIKey() async {
        let summarizer = MeetingSummarizer(
            apiKeyProvider: { nil },
            send: { _ in (Data(), URLResponse()) }
        )
        do {
            _ = try await summarizer.summarize(segments: [segment("x")])
            XCTFail("Expected missingAPIKey")
        } catch MeetingSummarizerError.missingAPIKey {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testSummarizeThrowsOnEmptyTranscript() async {
        let summarizer = MeetingSummarizer(
            apiKeyProvider: { "sk-test" },
            send: { _ in (Data(), URLResponse()) }
        )
        do {
            _ = try await summarizer.summarize(segments: [])
            XCTFail("Expected noContent")
        } catch MeetingSummarizerError.noContent {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testSummarizeThrowsOnHTTPError() async {
        let mockSend: MeetingSummarizer.HTTPSend = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (Data("server exploded".utf8), response)
        }
        let summarizer = MeetingSummarizer(
            apiKeyProvider: { "sk-test" },
            send: mockSend
        )
        do {
            _ = try await summarizer.summarize(segments: [segment("x")])
            XCTFail("Expected httpError")
        } catch let MeetingSummarizerError.httpError(code, body) {
            XCTAssertEqual(code, 500)
            XCTAssertTrue(body.contains("server exploded"))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - TranscriptSession backward-compat

    func testTranscriptSessionDecodesLegacyJSONWithoutSummaryField() throws {
        let legacy = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "title": "Old meeting",
          "startedAt": "2026-04-30T18:00:00Z",
          "endedAt": "2026-04-30T18:30:00Z",
          "status": "completed",
          "chunksTotal": 1,
          "chunksCompleted": 1,
          "segments": [],
          "audioRetained": true
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(TranscriptSession.self, from: Data(legacy.utf8))
        XCTAssertNil(session.summary)
        XCTAssertEqual(session.title, "Old meeting")
    }
}
