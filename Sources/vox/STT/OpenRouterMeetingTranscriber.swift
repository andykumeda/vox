import Foundation

public enum OpenRouterMeetingError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)
    case fileTooLarge

    public var description: String {
        switch self {
        case .missingAPIKey: return "OpenRouter API key missing — save it in Settings."
        case .invalidResponse: return "OpenRouter did not return valid timestamped meeting segments. Choose a model supporting verbose_json."
        case .httpError(let status): return "OpenRouter meeting HTTP \(status). Check the key, credits, model, and provider options."
        case .fileTooLarge: return "OpenRouter meeting audio exceeds the 25 MB inline upload limit. Reduce the meeting chunk duration in advanced Settings."
        }
    }
}

/// Timestamped meeting chunks; speaker labels are scoped to each chunk.
public enum OpenRouterMeetingTranscriber {
    // Azure's inline audio contract caps files at 25 MB.
    public static let maxBytes = 25_000_000

    private struct Response: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
            let speaker: Int?
        }
        let segments: [Segment]
    }

    public static func transcribeMeetingChunk(
        fileURL: URL, offsetSeconds: Double, source: SegmentSource,
        apiKey: String, urlSession: URLSession = .shared
    ) async throws -> [TranscriptSegment] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenRouterMeetingError.missingAPIKey }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maxBytes else {
            throw OpenRouterMeetingError.fileTooLarge
        }
        let endpoint = try ServiceConfiguration.url(.openrouterTranscriptionURL)
        let model = try ServiceConfiguration.string(.openrouterMeetingModel)
        let optionsJSON = try ServiceConfiguration.string(.openrouterMeetingProviderOptions)
        let options = try JSONSerialization.jsonObject(with: Data(optionsJSON.utf8))
        let body: [String: Any] = [
            "model": model,
            "input_audio": ["data": try Data(contentsOf: fileURL).base64EncodedString(), "format": "m4a"],
            "language": try ServiceConfiguration.string(.language),
            "temperature": try ServiceConfiguration.number(.temperature),
            "response_format": "verbose_json",
            "timestamp_granularities": ["segment"],
            "provider": ["options": options]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = try ServiceConfiguration.number(.meetingTimeout)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            try Task.checkCancellation()
            // The meeting session owns the configured transport retry budget.
            throw TranscriptionError.transportError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw OpenRouterMeetingError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Provider bodies may echo private content; don't put them in logs/UI.
            throw OpenRouterMeetingError.httpError(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              decoded.segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && ($0.speaker.map { $0 >= 0 } ?? true) }) else {
            throw OpenRouterMeetingError.invalidResponse
        }
        return decoded.segments.compactMap {
            let text = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(startTime: $0.start + offsetSeconds, endTime: $0.end + offsetSeconds, text: text,
                                     source: source, speakerID: source == .local ? nil : $0.speaker)
        }
    }
}
