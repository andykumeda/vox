import XCTest
@testable import vox

final class OpenRouterMeetingTranscriberTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        for root in meetingRoots { try? FileManager.default.removeItem(at: root) }
        meetingRoots = []
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

    func testMeetingRetriesRouterTransportFailureAndKeepsProvider() async throws {
        var attempts = 0
        URLProtocolStub.handler = { request in
            attempts += 1
            XCTAssertEqual(request.url, try ServiceConfiguration.url(.openrouterTranscriptionURL))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer router-test")
            if attempts == 1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"segments":[{"start":0,"end":1,"text":"recovered"}]}"#.utf8))
        }
        let session = try await runMeeting()
        XCTAssertEqual(session.statusSnapshot, .completed)
        XCTAssertEqual(attempts, 2)
        let stored = try XCTUnwrap(session.store.load(id: XCTUnwrap(session.activeSessionID)))
        XCTAssertEqual(stored.rawSegments.first?.text, "recovered")
    }

    func testMeetingDoesNotRetryRouterAuthenticationFailure() async throws {
        var attempts = 0
        URLProtocolStub.handler = { request in
            attempts += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    Data("private provider content".utf8))
        }
        let session = try await runMeeting()
        XCTAssertEqual(session.statusSnapshot, .failed)
        XCTAssertEqual(attempts, 1)
        let stored = try XCTUnwrap(session.store.load(id: XCTUnwrap(session.activeSessionID)))
        XCTAssertFalse(stored.failureReason?.contains("private provider content") ?? true)
    }

    private var meetingRoots: [URL] = []

    private func runMeeting() async throws -> MeetingTranscriptionSession {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("router-retry-\(UUID().uuidString)")
        meetingRoots.append(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let chunk = root.appendingPathComponent("chunk.m4a")
        try Data([1, 2, 3]).write(to: chunk)
        let transport = URLProtocolStub.makeSession()
        defer { transport.invalidateAndCancel() }
        let session = MeetingTranscriptionSession(
            store: MeetingTranscriptStore(rootDirectory: root, keyProvider: { Data(repeating: 0x7C, count: 32) }),
            recorder: MeetingTranscriptionSessionTests.MockRecorder(),
            chunker: { _, _ in [chunk] },
            transcribe: { _, _, _ in XCTFail("Must not fall back to OpenAI"); return [] },
            openrouterTranscribe: { url, offset, source in
                try await OpenRouterMeetingTranscriber.transcribeMeetingChunk(
                    fileURL: url, offsetSeconds: offset, source: source,
                    apiKey: "router-test", urlSession: transport)
            },
            provider: { .openrouter },
            apiKey: { nil },
            openrouterAPIKey: { "router-test" },
            preflight: { .success(()) },
            backoffSchedule: [0.001]
        )
        try await session.start()
        try await session.stop()
        await session.waitForCompletion()
        return session
    }
}
