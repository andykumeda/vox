import XCTest
@testable import vox

final class OpenAITranscriberTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testDictationRequestUsesFastDefaultTimeout() async throws {
        var observedRequest: URLRequest?
        var observedBody: Data?
        URLProtocolStub.handler = { request in
            observedRequest = request
            observedBody = Self.bodyData(from: request)
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("hello world\n".utf8))
        }

        let transcriber = OpenAITranscriber(
            endpoint: URL(string: "https://example.invalid")!,
            apiKeyProvider: { "sk-test" },
            urlSession: URLProtocolStub.makeSession()
        )

        let text = try await transcriber.transcribe(wav: Data([0x01, 0x02]), mode: .prose)

        XCTAssertEqual(text, "hello world")
        let request = try XCTUnwrap(observedRequest)
        XCTAssertEqual(
            request.timeoutInterval,
            OpenAITranscriber.defaultDictationRequestTimeout,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(OpenAITranscriber.defaultDictationRequestTimeout, 8.0)
        let body = String(data: try XCTUnwrap(observedBody), encoding: .utf8)
        XCTAssertTrue(try XCTUnwrap(body).contains("gpt-4o-transcribe"))
    }

    func testSendWithRetryRetriesTimeoutsBeforeSucceeding() async throws {
        var attempts = 0
        URLProtocolStub.handler = { request in
            attempts += 1
            if attempts == 1 {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("ok".utf8))
        }

        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.timeoutInterval = 0.5

        let (data, response) = try await OpenAITranscriber.sendWithRetry(
            request,
            session: URLProtocolStub.makeSession(),
            retryDelayNanoseconds: { _ in 0 },
            sleep: { _ in }
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(attempts, 2)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}
