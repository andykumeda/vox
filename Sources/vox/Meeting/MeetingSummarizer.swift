import Foundation

public enum MeetingSummarizerError: Error, CustomStringConvertible {
    case missingAPIKey
    case noContent
    case httpError(Int, String)
    case malformedResponse
    case transportError(Error)

    public var description: String {
        switch self {
        case .missingAPIKey:           return "Meeting summary: API key missing"
        case .noContent:               return "Meeting summary: empty transcript"
        case .httpError(let c, let b): return "Meeting summary HTTP \(c): \(b)"
        case .malformedResponse:       return "Meeting summary: malformed response"
        case .transportError(let e):   return "Meeting summary transport: \(e.localizedDescription)"
        }
    }
}

/// Calls OpenAI Chat Completions (gpt-4o-mini) with a meeting transcript
/// and returns a markdown summary. Tests inject a mock `send` closure.
public struct MeetingSummarizer: Sendable {
    public typealias HTTPSend = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let apiKeyProvider: @Sendable () -> String?
    public let endpoint: URL
    public let send: HTTPSend

    /// Hard cap on transcript characters sent to gpt-4o-mini. ~60k chars
    /// fits comfortably in the model's context window after the system
    /// prompt; longer meetings are truncated with a marker.
    public static let maxTranscriptChars: Int = 60_000

    public init(
        apiKeyProvider: @Sendable @escaping () -> String?,
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        send: @escaping HTTPSend = { try await URLSession.shared.data(for: $0) }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.endpoint = endpoint
        self.send = send
    }

    public func summarize(segments: [TranscriptSegment]) async throws -> String {
        guard !segments.isEmpty else { throw MeetingSummarizerError.noContent }
        guard let raw = apiKeyProvider() else { throw MeetingSummarizerError.missingAPIKey }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MeetingSummarizerError.missingAPIKey }

        let transcript = Self.formatTranscript(segments)
        let truncated: String
        if transcript.count > Self.maxTranscriptChars {
            truncated = String(transcript.prefix(Self.maxTranscriptChars)) +
                "\n\n[... transcript truncated for length ...]"
        } else {
            truncated = transcript
        }

        let systemPrompt = """
        You are a meeting-summarization function. Given a transcript with \
        speaker tags (Local = the user; Remote = other participants), \
        produce a concise summary in this exact markdown structure:

        ## Summary
        2-3 short paragraphs covering the topics discussed.

        ## Key decisions
        - Bulleted list. If none, write "None.".

        ## Action items
        - Bulleted list, owner-prefixed when clear (e.g. "Andy: send vendor list"). \
        If none, write "None.".

        Be terse and factual. Do not invent content not in the transcript. \
        Do not editorialize. Output only the markdown — no preface, no \
        codefence wrapping.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "max_tokens": 800,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": truncated],
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await send(request)
        } catch {
            throw MeetingSummarizerError.transportError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MeetingSummarizerError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw MeetingSummarizerError.httpError(http.statusCode, String(bodyText.prefix(200)))
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw MeetingSummarizerError.malformedResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formatTranscript(_ segments: [TranscriptSegment]) -> String {
        segments.map { seg in
            let speaker = seg.source == .local ? "Local" : "Remote"
            return "\(speaker): \(seg.text)"
        }.joined(separator: "\n")
    }
}
