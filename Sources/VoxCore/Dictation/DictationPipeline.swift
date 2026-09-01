import Foundation

public struct DictationRecording: Sendable {
    public let wav: Data
    public let metrics: WAVAudioMetrics

    public init(wav: Data, metrics: WAVAudioMetrics) {
        self.wav = wav
        self.metrics = metrics
    }
}

public struct DictationConfiguration: Sendable {
    public let mode: TranscriptionMode
    public let smartCleanupEnabled: Bool
    public let dictionaryEntries: [DictionaryEntry]
    public let additionalScratchThatTriggers: [String]

    public init(
        mode: TranscriptionMode = .prose,
        smartCleanupEnabled: Bool = true,
        dictionaryEntries: [DictionaryEntry] = [],
        additionalScratchThatTriggers: [String] = []
    ) {
        self.mode = mode
        self.smartCleanupEnabled = smartCleanupEnabled
        self.dictionaryEntries = dictionaryEntries
        self.additionalScratchThatTriggers = additionalScratchThatTriggers
    }
}

public struct DictationResult: Sendable, Equatable {
    public let text: String
    public let rawText: String
    public let suffixKeys: [SuffixKey]

    public init(text: String, rawText: String, suffixKeys: [SuffixKey]) {
        self.text = text
        self.rawText = rawText
        self.suffixKeys = suffixKeys
    }
}

public enum DictationPipelineError: Error, Equatable {
    case noSpeech
    case invalidAudio
    case suspectedHallucination
}

public struct DictationPipeline: Sendable {
    public typealias Transcribe = @Sendable (Data, TranscriptionMode) async throws -> String

    private let transcribeAudio: Transcribe
    private let llmCleaner: CleanupProcessor.LLMCleanFunc?

    public init(
        transcribe: @escaping Transcribe,
        llmCleaner: CleanupProcessor.LLMCleanFunc? = nil
    ) {
        self.transcribeAudio = transcribe
        self.llmCleaner = llmCleaner
    }

    public func transcribe(
        recording: DictationRecording,
        configuration: DictationConfiguration
    ) async throws -> DictationResult {
        let metrics = recording.metrics
        if DictationSilenceGate.shouldSkip(
            durationSec: metrics.durationSec,
            rms: metrics.rms,
            voicedDurationSec: metrics.voicedDurationSec
        ) {
            throw DictationPipelineError.noSpeech
        }

        let raw = try await transcribeAudio(recording.wav, configuration.mode)
        if DictationHallucinationGuard.shouldSuppress(
            raw,
            mode: configuration.mode,
            durationSec: metrics.durationSec,
            rms: metrics.rms
        ) {
            throw DictationPipelineError.suspectedHallucination
        }

        let maximumCharacterCount = max(160, Int(metrics.durationSec * 40.0))
        if raw.count > maximumCharacterCount {
            throw DictationPipelineError.suspectedHallucination
        }

        let processed = PostProcessor(
            mode: configuration.mode,
            dictionaryProvider: { configuration.dictionaryEntries }
        ).process(raw)
        let cleanup = CleanupProcessor(
            mode: configuration.mode,
            enabled: configuration.smartCleanupEnabled,
            llmCleaner: configuration.smartCleanupEnabled ? llmCleaner : nil,
            additionalScratchThatTriggers: configuration.additionalScratchThatTriggers
        )
        let cleaned = await cleanup.process(processed.text)
        let finalText = configuration.smartCleanupEnabled
            ? CleanupDictionaryProtection.apply(
                cleaned,
                mode: configuration.mode,
                entries: configuration.dictionaryEntries
            )
            : cleaned

        return DictationResult(text: finalText, rawText: raw, suffixKeys: processed.suffixKeys)
    }
}
