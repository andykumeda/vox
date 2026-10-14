import XCTest
@testable import vox

final class OpenRouterMeetingTranscriberTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    func testRequestUsesRouterKeyModelAndTimestampContract() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url, try ServiceConfiguration.url(.openrouterTranscriptionURL))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer router-test")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(from: request))) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, try ServiceConfiguration.string(.openrouterMeetingModel))
            XCTAssertEqual(body["response_format"] as? String, "verbose_json")
            XCTAssertEqual(body["timestamp_granularities"] as? [String], ["segment"])
            XCTAssertEqual((body["input_audio"] as? [String: String])?["format"], "m4a")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"segments":[{"start":1,"end":2,"text":" hello ","speaker":2}]}"#.utf8))
        }
        let segments = try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(
            fileURL: url, offsetSeconds: 300, source: .remote, apiKey: " router-test ", urlSession: URLProtocolStub.makeSession())
        XCTAssertEqual(segments[0].startTime, 301)
        XCTAssertEqual(segments[0].endTime, 302)
        XCTAssertEqual(segments[0].text, "hello")
        XCTAssertEqual(segments[0].speakerID, 2)
    }

    func testLocalStreamRemainsYouAndMalformedTimestampResponseFails() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        for body in [#"{"text":"untimed"}"#, #"{"segments":[{"start":2,"end":1,"text":"bad"}]}"#] {
            URLProtocolStub.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            do {
                _ = try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(fileURL: url, offsetSeconds: 0, source: .local, apiKey: "test", urlSession: URLProtocolStub.makeSession())
                XCTFail("Expected invalid response")
            } catch OpenRouterMeetingError.invalidResponse { }
        }
        URLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"segments":[{"start":0,"end":1,"text":"local","speaker":2}]}"#.utf8))
        }
        let segments = try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(fileURL: url, offsetSeconds: 0, source: .local, apiKey: "test", urlSession: URLProtocolStub.makeSession())
        XCTAssertEqual(segments[0].source, .local)
        XCTAssertNil(segments[0].speakerID)
    }

    func testMissingKeyFailsBeforeReadingAudio() async throws {
        do {
            _ = try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(fileURL: URL(fileURLWithPath: "/missing"), offsetSeconds: 0, source: .remote, apiKey: " ")
            XCTFail("Expected missing key")
        } catch OpenRouterMeetingError.missingAPIKey { }
    }

    func testHTTPAuthFailureDoesNotExposeProviderBody() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        URLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("private transcript".utf8))
        }
        do {
            _ = try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(fileURL: url, offsetSeconds: 0, source: .remote, apiKey: "test", urlSession: URLProtocolStub.makeSession())
            XCTFail("Expected 401")
        } catch OpenRouterMeetingError.httpError(let status) { XCTAssertEqual(status, 401) }
    }
}
