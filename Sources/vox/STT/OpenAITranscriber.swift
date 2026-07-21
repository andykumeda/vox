import Foundation

public enum TranscriptionError: Error, CustomStringConvertible {
    case missingAPIKey
    case httpError(Int, String)
    case invalidResponse
    case transportError(Error)

    public var description: String {
        switch self {
        case .missingAPIKey: return "OpenAI API key missing — set it in Settings."
        case .httpError(let code, let body): return "OpenAI HTTP \(code): \(body)"
        case .invalidResponse: return "Invalid response from OpenAI"
        case .transportError(let e): return "Transport error: \(e.localizedDescription)"
        }
    }
}

public struct OpenAITranscriber {
    public static let defaultDictationRequestTimeout: TimeInterval = 8.0
    private static let maximumDictationRequestTimeout: TimeInterval = 24.0
    private static let dictationResourceTimeoutPadding: TimeInterval = 5.0

    public let endpoint: URL
    public let modelProvider: () -> String
    public let apiKeyProvider: () -> String?
    public let requestTimeout: TimeInterval
    public let urlSession: URLSession?

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        modelProvider: @escaping () -> String = { "gpt-4o-transcribe" },
        apiKeyProvider: @escaping () -> String?,
        requestTimeout: TimeInterval = Self.defaultDictationRequestTimeout,
        urlSession: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.modelProvider = modelProvider
        self.apiKeyProvider = apiKeyProvider
        self.requestTimeout = requestTimeout
        self.urlSession = urlSession
    }

    public func transcribe(wav: Data, mode: TranscriptionMode) async throws -> String {
        let model = modelProvider()
        dlog("transcription request model=\(model) mode=\(mode.rawValue)")

        let apiKeyStartedAt = Date()
        let raw = apiKeyProvider()
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        dlog("transcription api key read elapsed=\(Self.formatElapsed(since: apiKeyStartedAt))s has_key=\(!key.isEmpty)")
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

        let boundary = "vox-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildBody(boundary: boundary, wav: wav, mode: mode, model: model)
        request.timeoutInterval = Self.dictationRequestTimeout(forWAV: wav, baseTimeout: requestTimeout)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.sendWithRetry(
                request,
                session: urlSession,
                totalTimeout: Self.resourceTimeout(forRequestTimeout: request.timeoutInterval)
            )
        } catch {
            throw TranscriptionError.transportError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.httpError(http.statusCode, body)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw TranscriptionError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sendWithRetry(
        _ request: URLRequest,
        session: URLSession? = nil,
        totalTimeout: TimeInterval? = nil,
        retryDelayNanoseconds: (Int) -> UInt64 = { attempt in
            UInt64(300_000_000) * UInt64(attempt + 1)
        },
        sleep: (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        monotonicNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        transport: @escaping @Sendable (URLSession, URLRequest) async throws -> (Data, URLResponse) = {
            try await $0.data(for: $1)
        },
        deadlineSleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) async throws -> (Data, URLResponse) {
        // `totalTimeout` is an operation-wide monotonic budget. A retry may use
        // only what the prior attempt and its backoff left behind.
        let retriable: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .dnsLookupFailed,
            .notConnectedToInternet, .cannotConnectToHost
        ]
        var lastError: Error?
        let maxAttempts = 3
        let operationStartedAt = monotonicNow()
        for attempt in 0..<maxAttempts {
            let attemptNumber = attempt + 1
            let startedAt = monotonicNow()
            let elapsedBeforeAttempt = max(0, startedAt - operationStartedAt)
            var activeRequest = request
            let activeResourceTimeout: TimeInterval
            if let totalTimeout {
                let remaining = totalTimeout - elapsedBeforeAttempt
                guard remaining > 0 else { break }
                let requestTimeout = request.timeoutInterval > 0
                    ? request.timeoutInterval
                    : Self.defaultDictationRequestTimeout
                activeRequest.timeoutInterval = min(requestTimeout, remaining)
                activeResourceTimeout = remaining
            } else {
                activeResourceTimeout = resourceTimeout(
                    forRequestTimeout: activeRequest.timeoutInterval
                )
            }
            let bodyBytes = activeRequest.httpBody?.count ?? 0
            dlog(
                "transcription http attempt=\(attemptNumber)/\(maxAttempts) started " +
                "timeout=\(String(format: "%.1f", activeRequest.timeoutInterval))s " +
                "resource_timeout=\(String(format: "%.1f", activeResourceTimeout))s " +
                "body_bytes=\(bodyBytes)"
            )

            let activeSession: URLSession
            let ownsSession: Bool
            if let session {
                activeSession = session
                ownsSession = false
            } else {
                activeSession = makeEphemeralSession(
                    requestTimeout: activeRequest.timeoutInterval,
                    resourceTimeout: activeResourceTimeout
                )
                ownsSession = true
            }
            defer {
                if ownsSession {
                    activeSession.finishTasksAndInvalidate()
                }
            }

            do {
                let result = try await data(
                    for: activeRequest,
                    using: activeSession,
                    deadline: activeResourceTimeout,
                    transport: transport,
                    deadlineSleep: deadlineSleep
                )
                let elapsed = max(0, monotonicNow() - startedAt)
                let status = (result.1 as? HTTPURLResponse)?.statusCode ?? -1
                dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) completed status=\(status) elapsed=\(formatElapsed(elapsed))s")
                return result
            } catch let urlError as URLError where retriable.contains(urlError.code) {
                lastError = urlError
                let finishedAt = monotonicNow()
                let attemptElapsed = max(0, finishedAt - startedAt)
                let totalElapsed = max(0, finishedAt - operationStartedAt)
                if attempt < maxAttempts - 1 {
                    let backoff = retryDelayNanoseconds(attempt)
                    let backoffSeconds = Double(backoff) / 1_000_000_000.0
                    if let totalTimeout, totalElapsed + backoffSeconds >= totalTimeout {
                        dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) deadline_exhausted retryable_error=\(urlError.code.rawValue) elapsed=\(formatElapsed(attemptElapsed))s total=\(formatElapsed(totalElapsed))s")
                        break
                    }
                    dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) retryable_error=\(urlError.code.rawValue) elapsed=\(formatElapsed(attemptElapsed))s backoff=\(String(format: "%.3f", backoffSeconds))s")
                    if backoff > 0 {
                        try await sleep(backoff)
                        try Task.checkCancellation()
                    }
                } else {
                    dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) exhausted retryable_error=\(urlError.code.rawValue) elapsed=\(formatElapsed(attemptElapsed))s")
                }
            } catch {
                let elapsed = max(0, monotonicNow() - startedAt)
                dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) failed error=\(error.localizedDescription) elapsed=\(formatElapsed(elapsed))s")
                throw error
            }
        }
        throw lastError ?? URLError(.timedOut)
    }

    private struct TransportResult: @unchecked Sendable {
        let data: Data
        let response: URLResponse
    }

    private static func data(
        for request: URLRequest,
        using session: URLSession,
        deadline: TimeInterval,
        transport: @escaping @Sendable (URLSession, URLRequest) async throws -> (Data, URLResponse),
        deadlineSleep: @escaping @Sendable (UInt64) async throws -> Void
    ) async throws -> (Data, URLResponse) {
        guard deadline.isFinite, deadline > 0 else { throw URLError(.timedOut) }
        // Keep the floating-point conversion comfortably within UInt64 even
        // for a nonsensically large injected timeout.
        let maximumSeconds = Double(Int64.max) / 1_000_000_000.0
        let nanoseconds = UInt64(min(deadline, maximumSeconds) * 1_000_000_000.0)

        return try await withThrowingTaskGroup(of: TransportResult.self) { group in
            group.addTask {
                let (data, response) = try await transport(session, request)
                return TransportResult(data: data, response: response)
            }
            group.addTask {
                try await deadlineSleep(nanoseconds)
                try Task.checkCancellation()
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw URLError(.timedOut) }
            return (result.data, result.response)
        }
    }

    private static func makeEphemeralSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        let requestTimeout = requestTimeout > 0
            ? requestTimeout
            : Self.defaultDictationRequestTimeout
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = max(resourceTimeout, 0.001)
        return URLSession(configuration: config)
    }

    private static func dictationRequestTimeout(
        forWAV wav: Data,
        baseTimeout: TimeInterval
    ) -> TimeInterval {
        let floor = baseTimeout > 0 ? baseTimeout : Self.defaultDictationRequestTimeout
        guard let duration = wavDurationSeconds(wav) else {
            return floor
        }
        let durationScaledTimeout = Self.defaultDictationRequestTimeout + duration * 0.25
        return max(floor, min(Self.maximumDictationRequestTimeout, durationScaledTimeout))
    }

    private static func resourceTimeout(forRequestTimeout requestTimeout: TimeInterval) -> TimeInterval {
        let requestTimeout = requestTimeout > 0 ? requestTimeout : Self.defaultDictationRequestTimeout
        return requestTimeout + Self.dictationResourceTimeoutPadding
    }

    private static func wavDurationSeconds(_ wav: Data) -> Double? {
        let headerSize = 44
        guard wav.count >= headerSize else { return nil }
        guard
            wavMatchesASCII(wav, "RIFF", at: 0),
            wavMatchesASCII(wav, "WAVE", at: 8),
            let byteRate = littleEndianUInt32(wav, at: 28),
            byteRate > 0,
            let declaredDataBytes = littleEndianUInt32(wav, at: 40)
        else { return nil }

        let availableDataBytes = max(0, wav.count - headerSize)
        let headerDataBytes = Int(declaredDataBytes)
        let dataBytes = headerDataBytes > 0
            ? min(headerDataBytes, availableDataBytes)
            : availableDataBytes
        guard dataBytes > 0 else { return nil }
        return Double(dataBytes) / Double(byteRate)
    }

    private static func wavMatchesASCII(_ data: Data, _ value: String, at offset: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard offset >= 0, offset + bytes.count <= data.count else { return false }
        for (index, byte) in bytes.enumerated() where data[offset + index] != byte {
            return false
        }
        return true
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func formatElapsed(since startedAt: Date) -> String {
        formatElapsed(Date().timeIntervalSince(startedAt))
    }

    private static func formatElapsed(_ elapsed: TimeInterval) -> String {
        String(format: "%.3f", max(0, elapsed))
    }

    private struct WhisperVerboseResponse: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
        }
        let segments: [Segment]
    }

    /// Transcribe one meeting audio chunk via Whisper `verbose_json` and stitch each
    /// segment's start/end onto an absolute meeting timeline using `offsetSeconds`.
    /// Caller (`MeetingTranscriptionSession`) is responsible for the outer infinite-retry
    /// loop on transport errors.
    public static func transcribeMeetingChunk(
        fileURL: URL,
        offsetSeconds: Double,
        apiKey: String,
        source: SegmentSource = .remote,
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        urlSession: URLSession = .shared
    ) async throws -> [TranscriptSegment] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

        let audioData = try Data(contentsOf: fileURL)
        let boundary = "vox-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMeetingBody(
            boundary: boundary,
            audio: audioData,
            filename: fileURL.lastPathComponent
        )
        request.timeoutInterval = 120.0

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await sendWithRetry(request, session: urlSession)
        } catch {
            throw TranscriptionError.transportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.httpError(http.statusCode, body)
        }

        let decoded: WhisperVerboseResponse
        do {
            decoded = try JSONDecoder().decode(WhisperVerboseResponse.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse
        }

        return decoded.segments.map { seg in
            TranscriptSegment(
                startTime: seg.start + offsetSeconds,
                endTime: seg.end + offsetSeconds,
                text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                source: source
            )
        }
    }

    private static func buildMeetingBody(boundary: String, audio: Data, filename: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-1")
        field("response_format", "verbose_json")
        field("timestamp_granularities[]", "segment")
        // Pin language + temperature=0 so silence/noise chunks don't get transcribed as
        // random Japanese (or other) text. Whisper's silence-hallucination behavior is
        // strongly correlated with language=auto + non-zero temperature.
        field("language", "en")
        field("temperature", "0")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func buildBody(boundary: String, wav: Data, mode: TranscriptionMode, model: String) -> Data {
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        appendField("model", model)
        appendField("response_format", "text")
        appendField("language", "en")
        appendField("prompt", mode.whisperPrompt)
        appendField("temperature", "0")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
