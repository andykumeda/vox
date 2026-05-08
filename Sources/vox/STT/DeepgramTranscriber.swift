import Foundation

public enum DeepgramError: Error, CustomStringConvertible {
    case missingAPIKey
    case httpError(Int, String)
    case invalidResponse
    case transportError(Error)
    case fileTooLarge(bytes: Int)

    public var description: String {
        switch self {
        case .missingAPIKey:           return "Deepgram API key missing — set in Settings."
        case .httpError(let c, let b): return "Deepgram HTTP \(c): \(b)"
        case .invalidResponse:         return "Deepgram: invalid response"
        case .transportError(let e):   return "Deepgram transport: \(e.localizedDescription)"
        case .fileTooLarge(let n):     return "Deepgram: audio file \(n) bytes exceeds 2 GB cap"
        }
    }
}

/// Submits a single mixed meeting audio file to Deepgram with diarization
/// enabled. The whole meeting is one request so speaker IDs are stable
/// across the entire transcript (chunking would reset numbering per call).
public struct DeepgramTranscriber {
    public static let endpoint = URL(string:
        "https://api.deepgram.com/v1/listen?model=nova-3&diarize=true" +
        "&utterances=true&punctuate=true&smart_format=true&language=en"
    )!

    /// Deepgram prerecorded API hard cap.
    public static let maxBytes: Int = 2 * 1024 * 1024 * 1024

    private struct Response: Decodable {
        struct Results: Decodable {
            struct Utterance: Decodable {
                let start: Double
                let end: Double
                let transcript: String
                let speaker: Int?
            }
            let utterances: [Utterance]?
        }
        let results: Results
    }

    public static func transcribeMeeting(
        fileURL: URL,
        apiKey: String,
        urlSession: URLSession = .shared
    ) async throws -> [TranscriptSegment] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepgramError.missingAPIKey }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { throw DeepgramError.fileTooLarge(bytes: size) }

        let audioData = try Data(contentsOf: fileURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 600

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw DeepgramError.transportError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw DeepgramError.httpError(http.statusCode, String(bodyText.prefix(400)))
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DeepgramError.invalidResponse
        }
        guard let utterances = decoded.results.utterances else {
            return []
        }
        return utterances.compactMap { u in
            let cleaned = u.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return TranscriptSegment(
                startTime: u.start,
                endTime: u.end,
                text: cleaned,
                source: .remote,
                speakerID: u.speaker
            )
        }
    }
}
