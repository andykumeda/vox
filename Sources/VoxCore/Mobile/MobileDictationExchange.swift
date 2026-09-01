import Foundation

public enum MobileDictationPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case requestingHandoff
    case recording
    case stopRequested
    case transcribing
    case ready
    case consumed
    case cancelled
    case failed
}

public struct MobileDictationExchange: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var requestID: UUID?
    public var createdAt: Date?
    public var updatedAt: Date
    public var phase: MobileDictationPhase
    public var resultText: String?
    public var errorMessage: String?

    public init(
        schemaVersion: Int = MobileDictationExchange.schemaVersion,
        requestID: UUID? = nil,
        createdAt: Date? = nil,
        updatedAt: Date = Date(),
        phase: MobileDictationPhase = .idle,
        resultText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.resultText = resultText
        self.errorMessage = errorMessage
    }
}

public enum MobileDictationExchangeError: Error, Equatable {
    case unsupportedSchema(Int)
    case requestInProgress
    case requestMismatch
    case invalidTransition(from: MobileDictationPhase, to: MobileDictationPhase)
    case missingResult
}

public struct MobileDictationExchangeStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> MobileDictationExchange {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return MobileDictationExchange()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exchange = try decoder.decode(
            MobileDictationExchange.self,
            from: Data(contentsOf: fileURL)
        )
        guard exchange.schemaVersion == MobileDictationExchange.schemaVersion else {
            throw MobileDictationExchangeError.unsupportedSchema(exchange.schemaVersion)
        }
        return exchange
    }

    @discardableResult
    public func beginRequest(now: Date = Date(), requestID: UUID = UUID()) throws -> MobileDictationExchange {
        let current = try load()
        guard [.idle, .consumed, .cancelled, .failed].contains(current.phase) else {
            throw MobileDictationExchangeError.requestInProgress
        }
        let exchange = MobileDictationExchange(
            requestID: requestID,
            createdAt: now,
            updatedAt: now,
            phase: .requestingHandoff
        )
        try save(exchange)
        return exchange
    }

    @discardableResult
    public func transition(
        requestID: UUID,
        to phase: MobileDictationPhase,
        resultText: String? = nil,
        errorMessage: String? = nil,
        now: Date = Date()
    ) throws -> MobileDictationExchange {
        var exchange = try load()
        guard exchange.requestID == requestID else {
            throw MobileDictationExchangeError.requestMismatch
        }
        guard Self.allowedTransitions[exchange.phase, default: []].contains(phase) else {
            throw MobileDictationExchangeError.invalidTransition(from: exchange.phase, to: phase)
        }
        if phase == .ready, resultText == nil {
            throw MobileDictationExchangeError.missingResult
        }
        exchange.phase = phase
        exchange.resultText = resultText
        exchange.errorMessage = errorMessage
        exchange.updatedAt = now
        try save(exchange)
        return exchange
    }

    public func consumeReadyResult(requestID: UUID, now: Date = Date()) throws -> String? {
        let exchange = try load()
        guard exchange.requestID == requestID else {
            throw MobileDictationExchangeError.requestMismatch
        }
        guard exchange.phase == .ready else { return nil }
        guard let result = exchange.resultText else {
            throw MobileDictationExchangeError.missingResult
        }
        _ = try transition(requestID: requestID, to: .consumed, now: now)
        return result
    }

    public func reset(now: Date = Date()) throws {
        try save(MobileDictationExchange(updatedAt: now))
    }

    private func save(_ exchange: MobileDictationExchange) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(exchange).write(to: fileURL, options: .atomic)
    }

    private static let allowedTransitions: [MobileDictationPhase: Set<MobileDictationPhase>] = [
        .idle: [.requestingHandoff],
        .requestingHandoff: [.recording, .cancelled, .failed],
        .recording: [.stopRequested, .cancelled, .failed],
        .stopRequested: [.transcribing, .cancelled, .failed],
        .transcribing: [.ready, .cancelled, .failed],
        .ready: [.consumed, .cancelled],
        .consumed: [],
        .cancelled: [],
        .failed: [],
    ]
}
