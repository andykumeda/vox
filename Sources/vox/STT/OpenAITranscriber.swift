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
    public let endpoint: URL
    public let model: String
    public let apiKeyProvider: () -> String?

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        model: String = "gpt-4o-transcribe",
        apiKeyProvider: @escaping () -> String?
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKeyProvider = apiKeyProvider
    }

    public func transcribe(wav: Data, mode: TranscriptionMode) async throws -> String {
        guard let raw = apiKeyProvider() else { throw TranscriptionError.missingAPIKey }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

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
