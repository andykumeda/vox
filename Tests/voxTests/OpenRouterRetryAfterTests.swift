import AVFoundation
import XCTest
@testable import vox

final class OpenRouterRetryAfterTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testRateLimitPreservesRetryAfterHeader() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeFixture(url)
        URLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                             headerFields: ["Retry-After": "75"])!, Data())
        }
        do {
            _ = try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(fileURL: url, offsetSeconds: 0, source: .remote, apiKey: "test", urlSession: URLProtocolStub.makeSession())
            XCTFail("Expected a rate limit")
        } catch OpenRouterMeetingError.rateLimited(let delay) {
            XCTAssertEqual(delay, 75)
        }
    }
    private func writeFixture(_ url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for channel in 0..<2 {
            for frame in 0..<48_000 { buffer.floatChannelData![channel][frame] = 0.2 }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    func testRetryAfterParsesHttpDatesAndRejectsInvalidValues() {
        let now = Date(timeIntervalSince1970: 784111777)
        XCTAssertEqual(OpenRouterMeetingTranscriber.retryAfter("Sun, 06 Nov 1994 08:49:37 GMT", now: now), 0)
        XCTAssertEqual(OpenRouterMeetingTranscriber.retryAfter("Sun, 06 Nov 1994 08:50:37 GMT", now: now), 60)
        XCTAssertEqual(OpenRouterMeetingTranscriber.retryAfter("Sunday, 06-Nov-94 08:50:37 GMT", now: now), 60)
        XCTAssertEqual(OpenRouterMeetingTranscriber.retryAfter("Sun Nov  6 08:50:37 1994", now: now), 60)
        XCTAssertNil(OpenRouterMeetingTranscriber.retryAfter("-2", now: now))
        XCTAssertNil(OpenRouterMeetingTranscriber.retryAfter("inf", now: now))
        XCTAssertNil(OpenRouterMeetingTranscriber.retryAfter("not a date", now: now))
        XCTAssertNil(OpenRouterMeetingTranscriber.retryAfter(nil, now: now))
    }
}
