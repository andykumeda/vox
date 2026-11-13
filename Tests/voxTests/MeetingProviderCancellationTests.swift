import XCTest
@testable import vox
@testable import VoxCore

final class MeetingProviderCancellationTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testCancellationIsNotWrappedAsProviderFailure() async throws {
        for provider in ["openai", "deepgram"] {
            let entered = expectation(description: "\(provider) request started")
            URLProtocolStub.handler = { request in
                entered.fulfill()
                Thread.sleep(forTimeInterval: 0.3)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data([0]).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let transport = URLProtocolStub.makeSession()
            let task = Task {
                if provider == "openai" {
                    return try await OpenAITranscriber.transcribeMeetingChunk(fileURL: url, offsetSeconds: 0, apiKey: "test", urlSession: transport)
                }
                return try await DeepgramTranscriber.transcribeMeeting(fileURL: url, apiKey: "test", urlSession: transport)
            }
            await fulfillment(of: [entered], timeout: 5)
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Expected cancellation for \(provider)")
            } catch is CancellationError {
            } catch {
                XCTFail("Cancellation became \(error) for \(provider)")
            }
            transport.invalidateAndCancel()
        }
    }
}
