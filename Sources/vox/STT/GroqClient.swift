import Foundation

public enum GroqError: Error, CustomStringConvertible {
    case missingAPIKey
    case httpError(Int, String)
    case invalidResponse
    case transportError(Error)

    public var description: String {
        switch self {
        case .missingAPIKey: return "Groq API key missing — set it in Settings."
        case .httpError(let code, let body): return "Groq HTTP \(code): \(body)"
        case .invalidResponse: return "Invalid response from Groq"
        case .transportError(let e): return "Transport error: \(e.localizedDescription)"
        }
    }
}

public struct GroqClient {
    public let endpoint: URL
    public let model: String
    public let apiKeyProvider: () -> String?

    public init(
        endpoint: URL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
        model: String = "whisper-large-v3",
        apiKeyProvider: @escaping () -> String?
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKeyProvider = apiKeyProvider
    }

    public func transcribe(wav: Data, mode: TranscriptionMode) async throws -> String {
        guard let raw = apiKeyProvider() else { throw GroqError.missingAPIKey }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GroqError.missingAPIKey }

        let boundary = "vox-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildBody(boundary: boundary, wav: wav, mode: mode)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GroqError.transportError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw GroqError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GroqError.httpError(http.statusCode, body)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw GroqError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildBody(boundary: String, wav: Data, mode: TranscriptionMode) -> Data {
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
