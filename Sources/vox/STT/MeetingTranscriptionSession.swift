import Foundation

/// Coordinates a single end-to-end meeting capture: record audio, slice into chunks,
/// upload each chunk to Whisper with infinite-retry-on-transport-failure, persist segments.
/// Singleton via `.shared` for the app; tests instantiate directly with mocks.
public final class MeetingTranscriptionSession {
    public typealias Chunker = (URL, URL) async throws -> [URL]
    public typealias Transcribe = (URL, Double) async throws -> [TranscriptSegment]

    public static let shared = MeetingTranscriptionSession(
        store: MeetingTranscriptStore(),
        recorder: nil,
        chunker: { input, dir in
            try await MeetingChunker().split(input: input, outputDirectory: dir)
        },
        transcribe: { url, offset in
            let key = KeychainStore().read() ?? ""
            return try await OpenAITranscriber.transcribeMeetingChunk(
                fileURL: url, offsetSeconds: offset, apiKey: key
            )
        },
        apiKey: { KeychainStore().read() },
        retainAudio: { AppSettings.meetingRetainAudio }
    )

    public let store: MeetingTranscriptStore
    private let recorderFactory: () -> MeetingAudioRecording
    private let chunker: Chunker
    private let transcribe: Transcribe
    private let apiKeyProvider: () -> String?
    private let retainAudioProvider: () -> Bool
    private let backoffSchedule: [Double]
    private let chunkDuration: Double = 300

    private var recorder: MeetingAudioRecording?
    private var uploadTask: Task<Void, Never>?
    private let lock = NSLock()
    private var session: TranscriptSession?

    public var activeSessionID: UUID? {
        lock.lock(); defer { lock.unlock() }
        return session?.id
    }

    public var statusSnapshot: TranscriptSession.Status? {
        lock.lock(); defer { lock.unlock() }
        return session?.status
    }

    public var isRecording: Bool {
        statusSnapshot == .recording
    }

    public var isActive: Bool {
        switch statusSnapshot {
        case .recording, .chunking, .transcribing: return true
        default: return false
        }
    }

    public init(
        store: MeetingTranscriptStore,
        recorder: MeetingAudioRecording?,
        chunker: @escaping Chunker,
        transcribe: @escaping Transcribe,
        apiKey: @escaping () -> String?,
        retainAudio: @escaping () -> Bool,
        backoffSchedule: [Double] = [1, 2, 4, 8, 16, 30]
    ) {
        self.store = store
        if let recorder = recorder {
            self.recorderFactory = { recorder }
        } else {
            self.recorderFactory = {
                if #available(macOS 13.0, *) { return MeetingAudioCapture() }
                fatalError("ScreenCaptureKit requires macOS 13+")
            }
        }
        self.chunker = chunker
        self.transcribe = transcribe
        self.apiKeyProvider = apiKey
        self.retainAudioProvider = retainAudio
        self.backoffSchedule = backoffSchedule
    }

    public enum SessionError: Error, CustomStringConvertible {
        case alreadyActive
        case notRecording
        case missingAPIKey

        public var description: String {
            switch self {
            case .alreadyActive: return "A meeting session is already active."
            case .notRecording: return "No active meeting session to stop."
            case .missingAPIKey: return "OpenAI API key missing."
            }
        }
    }

    public func start() async throws {
        lock.lock()
        guard session == nil else { lock.unlock(); throw SessionError.alreadyActive }
        let id = UUID()
        let now = Date()
        let title = "Meeting \(Self.titleFormatter.string(from: now))"
        let initial = TranscriptSession(
            id: id, title: title, startedAt: now, endedAt: nil,
            status: .recording, chunksTotal: 0, chunksCompleted: 0,
            segments: [], audioRetained: retainAudioProvider()
        )
        self.session = initial
        lock.unlock()

        try store.save(initial)

        let recorder = recorderFactory()
        self.recorder = recorder
        try await recorder.start(outputURL: store.audioFile(id: id))
    }

    public func stop() async throws {
        lock.lock()
        guard var current = session, current.status == .recording else {
            lock.unlock(); throw SessionError.notRecording
        }
        current.status = .chunking
        current.endedAt = Date()
        self.session = current
        lock.unlock()
        try store.save(current)

        guard let recorder = self.recorder else { throw SessionError.notRecording }
        let audioURL = try await recorder.stop()
        let captureFailureReason = recorder.lastFailureReason
        self.recorder = nil

        let sid = current.id
        if let reason = captureFailureReason {
            updateSession { s in
                s.status = .failed
                s.failureReason = reason
            }
            return
        }

        uploadTask = Task { [weak self] in
            await self?.runChunkAndUpload(audioURL: audioURL, sessionID: sid)
        }
    }

    public func cancel() {
        uploadTask?.cancel()
    }

    /// Block the caller until the upload task finishes (used by tests; production fires-and-forgets).
    public func waitForCompletion() async {
        await uploadTask?.value
    }

    private func runChunkAndUpload(audioURL: URL, sessionID: UUID) async {
        let chunksDir = store.chunksDirectory(id: sessionID)
        let chunkURLs: [URL]
        do {
            chunkURLs = try await chunker(audioURL, chunksDir)
        } catch let MeetingChunkerError.zeroDurationAsset {
            updateSession { s in
                s.status = .failed
                s.failureReason = "No audio captured. Check that audio was actually playing through the system during the recording, and Screen Recording permission is granted to Vox in System Settings → Privacy & Security."
            }
            return
        } catch {
            updateSession { s in
                s.status = .failed
                s.failureReason = "Could not split audio: \(error)"
            }
            return
        }
        updateSession { s in
            s.chunksTotal = chunkURLs.count
            s.status = .transcribing
        }

        var completed = 0
        for (i, chunkURL) in chunkURLs.enumerated() {
            if Task.isCancelled { break }
            let offset = Double(i) * chunkDuration
            let segments: [TranscriptSegment]
            do {
                segments = try await transcribeWithInfiniteRetry(url: chunkURL, offset: offset)
            } catch is CancellationError {
                break
            } catch {
                updateSession { s in
                    s.status = .failed
                    s.failureReason = "Transcription failed: \(error)"
                }
                return
            }
            updateSession { s in
                s.segments.append(contentsOf: segments)
                completed += 1
                s.chunksCompleted = completed
            }
        }

        if Task.isCancelled {
            updateSession { s in s.status = .cancelled }
            return
        }

        updateSession { s in s.status = .completed }
        try? FileManager.default.removeItem(at: chunksDir)
        if !retainAudioProvider() {
            try? store.purgeAudio(for: sessionID)
        }
    }

    private func transcribeWithInfiniteRetry(
        url: URL, offset: Double
    ) async throws -> [TranscriptSegment] {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await transcribe(url, offset)
            } catch let TranscriptionError.transportError(_) {
                let delay = backoffSchedule[min(attempt, backoffSchedule.count - 1)]
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            } catch {
                throw error
            }
        }
    }

    private func updateSession(_ mutate: (inout TranscriptSession) -> Void) {
        lock.lock()
        guard var s = session else { lock.unlock(); return }
        mutate(&s)
        session = s
        lock.unlock()
        try? store.save(s)
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
