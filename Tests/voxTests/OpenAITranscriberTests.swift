import XCTest
@testable import vox
@testable import VoxCore

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

    func testLongDictationRequestUsesLongerTimeoutBudget() async throws {
        var observedRequest: URLRequest?
        URLProtocolStub.handler = { request in
            observedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "https://example.invalid")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("long dictation\n".utf8))
        }

        let transcriber = OpenAITranscriber(
            endpoint: URL(string: "https://example.invalid")!,
            apiKeyProvider: { "sk-test" },
            urlSession: URLProtocolStub.makeSession()
        )

        let text = try await transcriber.transcribe(
            wav: Self.makeVoxWAV(durationSeconds: 55),
            mode: .prose
        )

        XCTAssertEqual(text, "long dictation")
        let request = try XCTUnwrap(observedRequest)
        XCTAssertGreaterThan(request.timeoutInterval, OpenAITranscriber.defaultDictationRequestTimeout)
        XCTAssertGreaterThanOrEqual(request.timeoutInterval, 20.0)
    }

    func testExplicitTimeoutOverrideIsNotReducedForLongWAV() async throws {
        var observedRequest: URLRequest?
        URLProtocolStub.handler = { request in
            observedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("override\n".utf8))
        }

        let transcriber = OpenAITranscriber(
            endpoint: URL(string: "https://example.invalid")!,
            apiKeyProvider: { "sk-test" },
            requestTimeout: 60,
            urlSession: URLProtocolStub.makeSession()
        )

        _ = try await transcriber.transcribe(
            wav: Self.makeVoxWAV(durationSeconds: 55),
            mode: .prose
        )

        XCTAssertEqual(try XCTUnwrap(observedRequest).timeoutInterval, 60, accuracy: 0.001)
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

    func testSendWithRetryDoesNotStartAnotherUploadAfterTotalTimeoutIsConsumed() async throws {
        var attempts = 0
        URLProtocolStub.handler = { _ in
            attempts += 1
            throw URLError(.timedOut)
        }

        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.timeoutInterval = 8.0
        var timestamps: [TimeInterval] = [1_000, 1_000, 1_013]

        do {
            _ = try await OpenAITranscriber.sendWithRetry(
                request,
                session: URLProtocolStub.makeSession(),
                totalTimeout: 13.0,
                retryDelayNanoseconds: { _ in 0 },
                sleep: { _ in },
                monotonicNow: { timestamps.removeFirst() }
            )
            XCTFail("Expected the exhausted timeout budget to fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(timestamps.isEmpty)
    }

    func testRetryReceivesOnlyTheRemainingTotalTimeoutBudget() async throws {
        var observedTimeouts: [TimeInterval] = []
        URLProtocolStub.handler = { request in
            observedTimeouts.append(request.timeoutInterval)
            if observedTimeouts.count == 1 {
                throw URLError(.networkConnectionLost)
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
        request.timeoutInterval = 8.0
        var timestamps: [TimeInterval] = [0, 0, 9, 9.3, 10]

        _ = try await OpenAITranscriber.sendWithRetry(
            request,
            session: URLProtocolStub.makeSession(),
            totalTimeout: 13,
            retryDelayNanoseconds: { _ in 300_000_000 },
            sleep: { _ in },
            monotonicNow: { timestamps.removeFirst() }
        )

        XCTAssertEqual(observedTimeouts.count, 2)
        XCTAssertEqual(observedTimeouts[0], 8, accuracy: 0.001)
        XCTAssertEqual(observedTimeouts[1], 3.7, accuracy: 0.001)
        XCTAssertTrue(timestamps.isEmpty)
    }

    func testDeadlineCancelsAnInFlightInjectedTransport() async throws {
        let attempts = LockedCounter()
        let transportStarted = OneShotSignal()
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.timeoutInterval = 8
        var timestamps: [TimeInterval] = [0, 0, 13]

        do {
            _ = try await OpenAITranscriber.sendWithRetry(
                request,
                session: URLProtocolStub.makeSession(),
                totalTimeout: 13,
                retryDelayNanoseconds: { _ in 0 },
                sleep: { _ in },
                monotonicNow: { timestamps.removeFirst() },
                transport: { _, _ in
                    attempts.increment()
                    await transportStarted.signal()
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                    throw URLError(.unknown)
                },
                deadlineSleep: { _ in await transportStarted.wait() }
            )
            XCTFail("Expected the in-flight transport to hit its deadline")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        XCTAssertEqual(attempts.value, 1)
        XCTAssertTrue(timestamps.isEmpty)
    }

    func testOwnedSessionUsesTheRemainingHardDeadlineAsItsResourceTimeout() async throws {
        let observed = LockedTimeoutObservation()
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.timeoutInterval = 8

        _ = try await OpenAITranscriber.sendWithRetry(
            request,
            totalTimeout: 13,
            transport: { session, request in
                observed.set(
                    request: request.timeoutInterval,
                    resource: session.configuration.timeoutIntervalForResource
                )
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("ok".utf8), response)
            }
        )

        XCTAssertEqual(observed.request, 8, accuracy: 0.001)
        XCTAssertEqual(observed.resource, 13, accuracy: 0.001)
    }

    func testCancellationDuringRetryBackoffDoesNotStartAnotherUpload() async throws {
        var attempts = 0
        URLProtocolStub.handler = { _ in
            attempts += 1
            throw URLError(.networkConnectionLost)
        }
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.timeoutInterval = 8

        do {
            _ = try await OpenAITranscriber.sendWithRetry(
                request,
                session: URLProtocolStub.makeSession(),
                retryDelayNanoseconds: { _ in 1 },
                sleep: { _ in throw CancellationError() }
            )
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(attempts, 1)
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

    private static func makeVoxWAV(durationSeconds: Double) -> Data {
        let sampleRate = 16_000
        let channels = 1
        let bitsPerSample = 16
        let pcmByteCount = UInt32((durationSeconds * Double(sampleRate)).rounded()) * 2
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLE(UInt32(36) + pcmByteCount)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLE(UInt32(16))
        wav.appendLE(UInt16(1))
        wav.appendLE(UInt16(channels))
        wav.appendLE(UInt32(sampleRate))
        wav.appendLE(UInt32(byteRate))
        wav.appendLE(UInt16(blockAlign))
        wav.appendLE(UInt16(bitsPerSample))
        wav.append(contentsOf: "data".utf8)
        wav.appendLE(pcmByteCount)
        wav.append(Data(count: Int(pcmByteCount)))
        return wav
    }
}

private actor OneShotSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
    }

    func wait() async {
        if isSignaled { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedTimeoutObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var requestStorage: TimeInterval = 0
    private var resourceStorage: TimeInterval = 0

    var request: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return requestStorage
    }

    var resource: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return resourceStorage
    }

    func set(request: TimeInterval, resource: TimeInterval) {
        lock.lock()
        requestStorage = request
        resourceStorage = resource
        lock.unlock()
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
