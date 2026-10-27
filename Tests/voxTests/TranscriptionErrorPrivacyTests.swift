import XCTest
@testable import vox

final class TranscriptionErrorPrivacyTests: XCTestCase {
    func testProviderHTTPFailuresDoNotExposeResponseBodies() async throws {
        let privateBody = "private recording content echoed by provider"
        URLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(privateBody.utf8))
        }
        let session = URLProtocolStub.makeSession()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([1, 2, 3]).write(to: file)
        defer {
            URLProtocolStub.handler = nil
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: file)
        }
        let requests: [() async throws -> Void] = [
            {
                _ = try await OpenAITranscriber(apiKeyProvider: { "test" }, urlSession: session)
                    .transcribe(wav: Data([1, 2, 3]), mode: .prose)
            },
            {
                _ = try await OpenAITranscriber(provider: .openrouter, apiKeyProvider: { "test" }, urlSession: session)
                    .transcribe(wav: Data([1, 2, 3]), mode: .prose)
            },
            {
                _ = try await OpenAITranscriber.transcribeMeetingChunk(
                    fileURL: file, offsetSeconds: 0, apiKey: "test", urlSession: session)
            },
            {
                _ = try await DeepgramTranscriber.transcribeMeeting(fileURL: file, apiKey: "test", urlSession: session)
            }
        ]
        for request in requests {
            do {
                try await request()
                XCTFail("Expected HTTP failure")
            } catch {
                let diagnostic = String(describing: error)
                XCTAssertTrue(diagnostic.contains("401"))
                XCTAssertFalse(diagnostic.contains(privateBody))
            }
        }
    }
}
