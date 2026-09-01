import Combine
import Foundation
import UIKit
import VoxCore

@MainActor
final class MobileDictationCoordinator: ObservableObject {
    @Published private(set) var phase: MobileDictationPhase = .idle
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var activeRequestID: UUID?

    let settings: MobileSettings
    let history: MobileHistoryStore
    let dictionary: DictionaryStore

    private let recorder = MobileAudioRecorder()
    private let exchangeStore: MobileDictationExchangeStore?
    private var pollTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var startingRequestID: UUID?

    init() {
        settings = MobileSettings()
        history = MobileHistoryStore()
        let dictionaryURL = try? MobileAppGroup.dictionaryURL()
        dictionary = DictionaryStore(
            fileURL: dictionaryURL ?? DictionaryStore.defaultFileURL(),
            bundledDefaults: []
        )
        exchangeStore = try? MobileAppGroup.exchangeStore()
        dictionary.load()
        refreshExchangeState()
        startPolling()
        resumePendingRequestIfNeeded()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func handle(url: URL) {
        guard url.scheme == "vox",
              url.host == "dictate",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let requestID = UUID(uuidString: requestValue)
        else {
            statusMessage = "The dictation link was invalid."
            return
        }
        Task { await startRecording(requestID: requestID) }
    }

    func startTestDictation() {
        guard let exchangeStore else {
            statusMessage = "The shared keyboard container is unavailable."
            return
        }
        do {
            let exchange = try exchangeStore.beginRequest()
            guard let requestID = exchange.requestID else { return }
            Task { await startRecording(requestID: requestID) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let requestID = activeRequestID else { return }
        requestStop(requestID: requestID)
    }

    func cancel() {
        guard let requestID = activeRequestID else { return }
        recorder.cancel()
        do {
            _ = try exchangeStore?.transition(requestID: requestID, to: .cancelled)
        } catch {
            dlog("iOS cancel transition failed: \(error.localizedDescription)")
        }
        finishBackgroundTask()
        activeRequestID = nil
        refreshExchangeState()
    }

    func resetExchangeState() {
        recorder.cancel()
        guard let exchangeStore else { return }
        do {
            try exchangeStore.reset()
            activeRequestID = nil
            refreshExchangeState()
        } catch {
            statusMessage = "Could not reset dictation state."
        }
    }

    private func startRecording(requestID: UUID) async {
        guard startingRequestID != requestID else { return }
        startingRequestID = requestID
        defer {
            if startingRequestID == requestID {
                startingRequestID = nil
            }
        }
        guard let exchangeStore else { return }
        do {
            let exchange = try exchangeStore.load()
            guard exchange.requestID == requestID,
                  exchange.phase == .requestingHandoff
            else {
                throw MobileDictationExchangeError.requestMismatch
            }
            activeRequestID = requestID
            beginBackgroundTask()
            _ = try await recorder.start(requestID: requestID)
            _ = try exchangeStore.transition(requestID: requestID, to: .recording)
            phase = .recording
            statusMessage = "Recording — swipe back to your app, then tap Stop in the Vox keyboard."
        } catch {
            recorder.cancel()
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: error.localizedDescription
            )
            finishBackgroundTask()
            activeRequestID = nil
            refreshExchangeState()
        }
    }

    private func requestStop(requestID: UUID) {
        guard let exchangeStore else { return }
        do {
            let current = try exchangeStore.load()
            if current.phase == .recording {
                _ = try exchangeStore.transition(requestID: requestID, to: .stopRequested)
            }
            guard let recordingURL = recorder.stop() else {
                throw MobileRecorderError.couldNotStart
            }
            _ = try exchangeStore.transition(requestID: requestID, to: .transcribing)
            phase = .transcribing
            statusMessage = "Transcribing…"
            Task { await transcribe(requestID: requestID, recordingURL: recordingURL) }
        } catch {
            recorder.cancel()
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: error.localizedDescription
            )
            finishBackgroundTask()
            refreshExchangeState()
        }
    }

    private func transcribe(requestID: UUID, recordingURL: URL) async {
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            finishBackgroundTask()
            activeRequestID = nil
            refreshExchangeState()
        }
        guard let exchangeStore else { return }
        var capturedMetrics: WAVAudioMetrics?
        do {
            let wav = try Data(contentsOf: recordingURL)
            guard let metrics = WAVAudioMetrics.analyze(wav) else {
                throw DictationPipelineError.invalidAudio
            }
            capturedMetrics = metrics
            guard let apiKey = settings.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty
            else {
                throw TranscriptionError.missingAPIKey
            }

            let transcriber = OpenAITranscriber(
                modelProvider: { "gpt-4o-transcribe" },
                apiKeyProvider: { apiKey }
            )
            let cleaner = makeLiveLLMCleaner(
                apiKeyProvider: { apiKey },
                dictionaryProvider: { self.dictionary.entries }
            )
            let pipeline = DictationPipeline(
                transcribe: { wav, mode in
                    try await transcriber.transcribe(wav: wav, mode: mode)
                },
                llmCleaner: cleaner
            )
            let result = try await pipeline.transcribe(
                recording: DictationRecording(wav: wav, metrics: metrics),
                configuration: DictationConfiguration(
                    mode: .prose,
                    smartCleanupEnabled: settings.smartCleanupEnabled,
                    dictionaryEntries: dictionary.entries
                )
            )
            history.record(
                text: result.text,
                rawText: result.rawText,
                durationSec: metrics.durationSec
            )
            _ = try exchangeStore.transition(
                requestID: requestID,
                to: .ready,
                resultText: result.text
            )
            phase = .ready
            statusMessage = "Done — the Vox keyboard will insert your text."
        } catch DictationPipelineError.noSpeech {
            let diagnostic: String
            if let metrics = capturedMetrics {
                diagnostic = String(
                    format: "No speech detected (%.1fs, RMS %.0f, voiced %.2fs).",
                    metrics.durationSec,
                    metrics.rms,
                    metrics.voicedDurationSec
                )
            } else {
                diagnostic = "We didn’t catch any speech. Please try again."
            }
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: diagnostic
            )
            statusMessage = diagnostic
        } catch DictationPipelineError.suspectedHallucination {
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: "The transcription looked unreliable, so Vox did not insert it."
            )
        } catch {
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshExchangeState()
                if let requestID = self.activeRequestID,
                   let exchangeStore = self.exchangeStore,
                   let current = try? exchangeStore.load(),
                   current.requestID == requestID,
                   current.phase == .stopRequested,
                   self.recorder.isRecording {
                    self.requestStop(requestID: requestID)
                }
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    /// If the keyboard could not foreground Vox, resume its pending request
    /// when the user opens Vox manually.
    func resumePendingRequestIfNeeded() {
        guard let exchangeStore,
              let exchange = try? exchangeStore.load(),
              exchange.phase == .requestingHandoff,
              let requestID = exchange.requestID
        else { return }
        Task { await startRecording(requestID: requestID) }
    }

    private func refreshExchangeState() {
        guard let exchangeStore,
              let exchange = try? exchangeStore.load()
        else { return }
        phase = exchange.phase
        if activeRequestID == nil,
           [.requestingHandoff, .recording, .stopRequested, .transcribing].contains(exchange.phase) {
            activeRequestID = exchange.requestID
        }
        switch exchange.phase {
        case .idle: statusMessage = "Ready"
        case .requestingHandoff: statusMessage = "Opening Vox to start the microphone…"
        case .recording: statusMessage = "Recording…"
        case .stopRequested: statusMessage = "Stopping…"
        case .transcribing: statusMessage = "Transcribing…"
        case .ready: statusMessage = "Ready to insert from the Vox keyboard."
        case .consumed: statusMessage = "Inserted"
        case .cancelled: statusMessage = "Cancelled"
        case .failed: statusMessage = exchange.errorMessage ?? "Dictation failed."
        }
    }

    private func beginBackgroundTask() {
        finishBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Vox dictation") { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    private func finishBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
