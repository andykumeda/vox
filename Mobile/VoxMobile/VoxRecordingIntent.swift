import ActivityKit
import AppIntents
import Foundation
import VoxCore

struct VoxRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRecording: Bool
    }

    var startedAt: Date
}

@available(iOS 18.0, *)
struct ToggleVoxRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Vox Dictation"
    static let description = IntentDescription("Start or stop Vox dictation without leaving the current app.")

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await MobileIntentDictationService.shared.toggle()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 18.0, *)
struct VoxAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleVoxRecordingIntent(),
            phrases: ["Toggle dictation with \(.applicationName)"],
            shortTitle: "Toggle Dictation",
            systemImageName: "mic.fill"
        )
    }
}

@MainActor
private final class MobileIntentDictationService {
    static let shared = MobileIntentDictationService()

    private let recorder = MobileAudioRecorder()
    private let settings = MobileSettings()
    private var requestID: UUID?
    private var activity: Activity<VoxRecordingAttributes>?

    func toggle() async throws -> String {
        if recorder.isRecording {
            try await stop()
            return "Vox is transcribing."
        }
        try await start()
        return "Vox is recording."
    }

    private func start() async throws {
        let exchangeStore = try MobileAppGroup.exchangeStore()
        let current = try exchangeStore.load()
        if ![.idle, .consumed, .cancelled, .failed].contains(current.phase) {
            try exchangeStore.reset()
        }

        let request = try exchangeStore.beginRequest()
        guard let requestID = request.requestID else {
            throw MobileDictationExchangeError.requestMismatch
        }
        self.requestID = requestID
        UserDefaults(suiteName: MobileAppGroup.identifier)?
            .set(requestID.uuidString, forKey: "keyboard.activeRequestID")

        let attributes = VoxRecordingAttributes(startedAt: Date())
        activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(
                state: .init(isRecording: true),
                staleDate: nil
            )
        )

        do {
            _ = try await recorder.start(requestID: requestID)
            _ = try exchangeStore.transition(requestID: requestID, to: .recording)
        } catch {
            await endActivity()
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    private func stop() async throws {
        guard let requestID,
              let recordingURL = recorder.stop()
        else { throw MobileRecorderError.couldNotStart }

        await endActivity()
        let exchangeStore = try MobileAppGroup.exchangeStore()
        let current = try exchangeStore.load()
        if current.phase == .recording {
            _ = try exchangeStore.transition(requestID: requestID, to: .stopRequested)
        }
        _ = try exchangeStore.transition(requestID: requestID, to: .transcribing)

        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            self.requestID = nil
        }

        do {
            let wav = try Data(contentsOf: recordingURL)
            guard let metrics = WAVAudioMetrics.analyze(wav) else {
                throw DictationPipelineError.invalidAudio
            }
            guard let apiKey = settings.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty
            else { throw TranscriptionError.missingAPIKey }

            let transcriber = OpenAITranscriber(
                modelProvider: { "gpt-4o-transcribe" },
                apiKeyProvider: { apiKey }
            )
            let result = try await DictationPipeline(
                transcribe: { wav, mode in
                    try await transcriber.transcribe(wav: wav, mode: mode)
                }
            ).transcribe(
                recording: DictationRecording(wav: wav, metrics: metrics),
                configuration: DictationConfiguration(
                    mode: .prose,
                    smartCleanupEnabled: false
                )
            )
            _ = try exchangeStore.transition(
                requestID: requestID,
                to: .ready,
                resultText: result.text
            )
        } catch {
            _ = try? exchangeStore.transition(
                requestID: requestID,
                to: .failed,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    private func endActivity() async {
        guard let activity else { return }
        await activity.end(
            ActivityContent(state: .init(isRecording: false), staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.activity = nil
    }
}
