import Foundation

/// Pre- and post-STT guards for push-to-talk clips that contain little or no speech.
///
/// gpt-4o-transcribe / Whisper commonly invent filler text or echo the `prompt`
/// field when fed near-silent audio. Observed empty-hold failures include
/// "The quick brown fox jumps over the lazy dog." (prose) and "ls -l" (command —
/// the first example in the command-mode prompt).
public enum DictationSilenceGate {
    /// Minimum hold duration before a clip is worth sending to STT.
    /// Ambient room noise around ~0.37s was slipping past the old 0.35s floor.
    public static let minimumDurationSec: Double = 0.50

    /// For short clips (< `shortClipDurationSec`), require at least this RMS.
    /// Ambient mic floor on empty holds landed ~200–300; real speech was 400+.
    #if os(iOS)
    /// iPhone AVAudioRecorder levels are substantially lower than the Mac
    /// input path (typical spoken clips can measure around 150–300 RMS).
    public static let shortClipMinimumRMS: Double = 100
    #else
    public static let shortClipMinimumRMS: Double = 350
    #endif

    public static let shortClipDurationSec: Double = 2.0

    /// Minimum sustained frame-level energy for a short clip to count as speech.
    /// Overall RMS is insufficient: an empty toggle can contain a brief click or
    /// handling noise with a deceptively high average level.
    #if os(iOS)
    public static let minimumVoicedDurationSec: Double = 0.20
    public static let speechActivityFrameRMS: Double = 150
    #else
    public static let minimumVoicedDurationSec: Double = 0.28
    public static let speechActivityFrameRMS: Double = 700
    #endif

    /// Absolute floor — digital silence / muted mic.
    #if os(iOS)
    public static let absoluteMinimumRMS: Double = 20
    #else
    public static let absoluteMinimumRMS: Double = 40
    #endif

    public static func shouldSkip(
        durationSec: Double,
        rms: Double,
        voicedDurationSec: Double? = nil
    ) -> Bool {
        if durationSec < minimumDurationSec { return true }
        if durationSec < shortClipDurationSec && rms < shortClipMinimumRMS { return true }
        if let voicedDurationSec,
           voicedDurationSec < minimumVoicedDurationSec { return true }
        if rms < absoluteMinimumRMS { return true }
        return false
    }
}

public enum DictationHallucinationGuard {
    /// Known model fillers on silent / low-energy audio. Matched after
    /// case-insensitive, punctuation-stripped, whitespace-collapsed normalisation.
    public static let fillerPhrases: Set<String> = [
        "the quick brown fox jumps over the lazy dog",
        "the cat sat on the mat",
        "the cat is on the mat",
        "you",
        "thank you",
        "thanks",
        "thank you for watching",
        "thanks for watching",
        "subscribe",
        "please subscribe",
        "bye",
        "goodbye",
        "see you next time",
    ]

    /// Command-mode prompt examples that the model echoes on near-silent audio.
    /// Stored already-normalized (punctuation stripped) so they match `normalize(_:)`.
    /// Suppress only when the clip is short and quiet so a real spoken
    /// "ls -l" (typically ≥1s with high RMS) still pastes.
    public static let promptEchoCommands: Set<String> = Set([
        "ls -l", "ls -la", "ls -lh", "ls -a",
        "cd ..", "cd -",
        "rm -rf", "rm -rf node_modules",
        "cat README.md", "cat foo.txt",
        "grep -r foo",
        "ps -ef", "ps aux",
        "df -h", "du -sh",
        "head -n 20", "tail -f",
        "chmod +x", "chmod 755",
        "mkdir -p",
        "find . -name",
        "git status", "git log", "git diff",
        "docker ps",
        "kubectl get pods",
        "npm install",
        "brew update",
        "curl -sSL",
        "ssh user@host",
    ].map(normalize))

    public static let promptEchoMaxDurationSec: Double = 1.0
    public static let promptEchoMaxRMS: Double = 400

    public static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\p{P}\\p{S}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Returns true when `raw` should be discarded instead of pasted.
    public static func shouldSuppress(
        _ raw: String,
        mode: TranscriptionMode,
        durationSec: Double,
        rms: Double
    ) -> Bool {
        let stripped = normalize(raw)
        guard !stripped.isEmpty else { return false }

        if fillerPhrases.contains(stripped) { return true }

        if mode == .command,
           durationSec < promptEchoMaxDurationSec,
           rms < promptEchoMaxRMS,
           promptEchoCommands.contains(stripped) {
            return true
        }

        return false
    }
}
