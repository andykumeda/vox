import AVFoundation
import Foundation

public enum OpenRouterMeetingError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case fileTooLarge
    case audioConversionFailed

    public var description: String {
        switch self {
        case .missingAPIKey: return "OpenRouter API key missing — save it in Settings."
        case .invalidResponse: return "OpenRouter did not return valid timestamped meeting segments. Choose a model supporting verbose_json."
        case .httpError(let status): return "OpenRouter meeting HTTP \(status). Check the key, credits, model, and provider options."
        case .rateLimited: return "OpenRouter meeting HTTP 429. Check the key, credits, model, and provider options."
        case .fileTooLarge: return "OpenRouter meeting audio exceeds the 25 MB inline upload limit. Reduce the meeting chunk duration in advanced Settings."
        case .audioConversionFailed: return "Could not convert meeting audio for OpenRouter."
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
        let audio = try wavAudio(fileURL)
        let endpoint = try ServiceConfiguration.url(.openrouterTranscriptionURL)
        let model = try ServiceConfiguration.string(.openrouterMeetingModel)
        let optionsJSON = try ServiceConfiguration.string(.openrouterMeetingProviderOptions)
        let options = try JSONSerialization.jsonObject(with: Data(optionsJSON.utf8))
        let body: [String: Any] = [
            "model": model,
            "input_audio": ["data": audio.base64EncodedString(), "format": "wav"],
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
            if http.statusCode == 429 {
                throw OpenRouterMeetingError.rateLimited(retryAfter: retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
            }
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

    static func retryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.utf8.allSatisfy({ (48...57).contains($0) }) {
            guard let seconds = Double(value), seconds.isFinite else { return nil }
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'", "EEEE',' dd-MMM-yy HH':'mm':'ss 'GMT'", "EEE MMM d HH':'mm':'ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return max(0, date.timeIntervalSince(now)) }
        }
        return nil
    }

    private static func wavAudio(_ url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
            throw OpenRouterMeetingError.audioConversionFailed
        }
        var pcm = Data()
        var readError: Error?
        while true {
            try Task.checkCancellation()
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, state in
                guard file.framePosition < file.length else {
                    state.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input)
                    state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input.frameLength == 0 ? nil : input
                } catch {
                    readError = error
                    state.pointee = .endOfStream
                    return nil
                }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            guard status != .error else { throw OpenRouterMeetingError.audioConversionFailed }
            if output.frameLength > 0, let samples = output.int16ChannelData?[0] {
                pcm.append(Data(bytes: samples, count: Int(output.frameLength) * 2))
                guard pcm.count + 44 <= maxBytes else { throw OpenRouterMeetingError.fileTooLarge }
            }
            if status == .endOfStream { break }
        }
        guard !pcm.isEmpty else { throw OpenRouterMeetingError.audioConversionFailed }
        var wav = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: "RIFF".utf8); word(UInt32(pcm.count + 36))
        wav.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(16_000)); word(UInt32(32_000)); word(UInt16(2)); word(UInt16(16))
        wav.append(contentsOf: "data".utf8); word(UInt32(pcm.count)); wav.append(pcm)
        return wav
    }
}
