import Foundation

public enum SegmentSource: String, Codable, Sendable {
    /// Captured via SCStream (system audio mix — remote participants in a meeting).
    case remote
    /// Captured via the local microphone (the user's own voice).
    case local
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let text: String
    public let source: SegmentSource

    public init(startTime: Double, endTime: Double, text: String, source: SegmentSource = .remote) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, text, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.startTime = try c.decode(Double.self, forKey: .startTime)
        self.endTime = try c.decode(Double.self, forKey: .endTime)
        self.text = try c.decode(String.self, forKey: .text)
        // Pre-multi-source persisted segments have no `source`; treat as remote (system audio).
        self.source = try c.decodeIfPresent(SegmentSource.self, forKey: .source) ?? .remote
    }
}

public struct TranscriptSession: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case recording, chunking, transcribing, completed, cancelled, failed
    }

    public let id: UUID
    public var title: String
    public let startedAt: Date
    public var endedAt: Date?
    public var status: Status
    public var chunksTotal: Int
    public var chunksCompleted: Int
    public var segments: [TranscriptSegment]
    public var audioRetained: Bool
    public var failureReason: String?

    public init(
        id: UUID,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        status: Status,
        chunksTotal: Int,
        chunksCompleted: Int,
        segments: [TranscriptSegment],
        audioRetained: Bool,
        failureReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.chunksTotal = chunksTotal
        self.chunksCompleted = chunksCompleted
        self.segments = segments
        self.audioRetained = audioRetained
        self.failureReason = failureReason
    }
}

public extension Notification.Name {
    static let meetingTranscriptStoreDidChange =
        Notification.Name("vox.meetingTranscriptStoreDidChange")
}

public final class MeetingTranscriptStore {
    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default location: ~/Library/Application Support/Vox/MeetingTranscripts
    public static func defaultRoot() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return support
            .appendingPathComponent("Vox", isDirectory: true)
            .appendingPathComponent("MeetingTranscripts", isDirectory: true)
    }

    public init(rootDirectory: URL = MeetingTranscriptStore.defaultRoot()) {
        self.rootDirectory = rootDirectory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func sessionDirectory(id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func audioFile(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("audio.m4a")
    }

    /// Local mic recording captured in parallel with system audio.
    public func micFile(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("mic.m4a")
    }

    public func chunksDirectory(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("chunks", isDirectory: true)
    }

    /// Per-source chunk directory keeps system and mic chunk ordering independent.
    public func chunksDirectory(id: UUID, source: SegmentSource) -> URL {
        let name = source == .local ? "chunks-mic" : "chunks-system"
        return sessionDirectory(id: id).appendingPathComponent(name, isDirectory: true)
    }

    private func transcriptFile(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("transcript.json")
    }

    public func save(_ session: TranscriptSession) throws {
        let dir = sessionDirectory(id: session.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try data.write(to: transcriptFile(id: session.id), options: .atomic)
        NotificationCenter.default.post(name: .meetingTranscriptStoreDidChange, object: nil)
    }

    public func load(id: UUID) -> TranscriptSession? {
        guard let data = try? Data(contentsOf: transcriptFile(id: id)) else { return nil }
        return try? decoder.decode(TranscriptSession.self, from: data)
    }

    public func list() -> [TranscriptSession] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        let sessions = entries.compactMap { dir -> TranscriptSession? in
            guard let id = UUID(uuidString: dir.lastPathComponent) else { return nil }
            return load(id: id)
        }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: sessionDirectory(id: id))
        NotificationCenter.default.post(name: .meetingTranscriptStoreDidChange, object: nil)
    }

    public func purgeAudio(for id: UUID) throws {
        for url in [audioFile(id: id), micFile(id: id)] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        if var session = load(id: id) {
            session.audioRetained = false
            try save(session)
        }
    }

    /// Cold-recovery sweep: any session left in an in-flight state from a prior process
    /// (recording, chunking, transcribing) is reset to `.failed` so the UI shows a clean
    /// terminal state rather than a stuck spinner. Idempotent.
    public func recoverInFlightSessions() {
        for var session in list() {
            switch session.status {
            case .recording, .chunking, .transcribing:
                session.status = .failed
                if session.endedAt == nil { session.endedAt = Date() }
                try? save(session)
            case .completed, .cancelled, .failed:
                break
            }
        }
    }
}
