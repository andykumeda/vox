import XCTest
@testable import vox

final class OpenAITranscriberMeetingTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    private func writeFixtureAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: url)
        return url
    }

    func testTranscribeMeetingChunkAppliesOffsetAndDecodesSegments() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {
              "task": "transcribe",
              "language": "en",
              "duration": 12.0,
              "text": "hello world",
              "segments": [
                {"id": 0, "start": 0.0, "end": 4.5, "text": "hello"},
                {"id": 1, "start": 4.5, "end": 12.0, "text": "world"}
              ]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }
        let session = URLProtocolStub.makeSession()
        let fixture = try writeFixtureAudio()

        let segments = try await OpenAITranscriber.transcribeMeetingChunk(
            fileURL: fixture,
            offsetSeconds: 600.0,
            apiKey: "sk-test",
            urlSession: session
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].startTime, 600.0, accuracy: 0.001)
        XCTAssertEqual(segments[0].endTime, 604.5, accuracy: 0.001)
        XCTAssertEqual(segments[0].text, "hello")
        XCTAssertEqual(segments[1].startTime, 604.5, accuracy: 0.001)
        XCTAssertEqual(segments[1].endTime, 612.0, accuracy: 0.001)
    }

    func testTranscribeMeetingChunkThrowsOnHTTPError() async throws {
        URLProtocolStub.handler = { _ in
            let body = "{\"error\":\"unauthorized\"}".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }
        let session = URLProtocolStub.makeSession()
        let fixture = try writeFixtureAudio()

        do {
            _ = try await OpenAITranscriber.transcribeMeetingChunk(
                fileURL: fixture, offsetSeconds: 0, apiKey: "sk-test", urlSession: session
            )
            XCTFail("Expected throw")
        } catch let TranscriptionError.httpError(code, _) {
            XCTAssertEqual(code, 401)
        }
    }

    func testTranscribeMeetingChunkOffsetZeroIdentity() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {"segments": [{"id":0,"start":1.0,"end":2.0,"text":"x"}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }
        let session = URLProtocolStub.makeSession()
        let fixture = try writeFixtureAudio()
        let segs = try await OpenAITranscriber.transcribeMeetingChunk(
            fileURL: fixture, offsetSeconds: 0, apiKey: "sk-test", urlSession: session
        )
        XCTAssertEqual(segs[0].startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(segs[0].endTime, 2.0, accuracy: 0.001)
    }
}
