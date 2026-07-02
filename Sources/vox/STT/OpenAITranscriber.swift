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
        request.timeoutInterval = requestTimeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.sendWithRetry(request, session: urlSession)
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
        retryDelayNanoseconds: (Int) -> UInt64 = { attempt in
            UInt64(300_000_000) * UInt64(attempt + 1)
        },
        sleep: (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) async throws -> (Data, URLResponse) {
        let retriable: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .dnsLookupFailed,
            .notConnectedToInternet, .cannotConnectToHost
        ]
        var lastError: Error?
        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            let attemptNumber = attempt + 1
            let startedAt = Date()
            let bodyBytes = request.httpBody?.count ?? 0
            dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) started timeout=\(String(format: "%.1f", request.timeoutInterval))s body_bytes=\(bodyBytes)")

            let activeSession: URLSession
            let ownsSession: Bool
            if let session {
                activeSession = session
                ownsSession = false
            } else {
                activeSession = makeEphemeralSession(timeout: request.timeoutInterval)
                ownsSession = true
            }
            defer {
                if ownsSession {
                    activeSession.finishTasksAndInvalidate()
                }
            }

            do {
                let result = try await activeSession.data(for: request)
                let status = (result.1 as? HTTPURLResponse)?.statusCode ?? -1
                dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) completed status=\(status) elapsed=\(formatElapsed(since: startedAt))s")
                return result
            } catch let urlError as URLError where retriable.contains(urlError.code) {
                lastError = urlError
                if attempt < maxAttempts - 1 {
                    let backoff = retryDelayNanoseconds(attempt)
                    dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) retryable_error=\(urlError.code.rawValue) elapsed=\(formatElapsed(since: startedAt))s backoff=\(String(format: "%.3f", Double(backoff) / 1_000_000_000.0))s")
                    if backoff > 0 {
                        await sleep(backoff)
                    }
                } else {
                    dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) exhausted retryable_error=\(urlError.code.rawValue) elapsed=\(formatElapsed(since: startedAt))s")
                }
            } catch {
                dlog("transcription http attempt=\(attemptNumber)/\(maxAttempts) failed error=\(error.localizedDescription) elapsed=\(formatElapsed(since: startedAt))s")
                throw error
            }
        }
        throw lastError ?? URLError(.timedOut)
    }

    private static func makeEphemeralSession(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        let requestTimeout = timeout > 0 ? timeout : Self.defaultDictationRequestTimeout
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout + 5.0
        return URLSession(configuration: config)
    }

    private static func formatElapsed(since startedAt: Date) -> String {
        String(format: "%.3f", Date().timeIntervalSince(startedAt))
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
