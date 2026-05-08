import Foundation

enum TranscriptionModel: String, CaseIterable, Sendable {
    case mini = "gpt-4o-mini-transcribe"
    case full = "gpt-4o-transcribe"
    case whisper = "whisper-1"

    var displayName: String {
        switch self {
        case .mini: return "gpt-4o-mini-transcribe (cheapest, follows prompts)"
        case .full: return "gpt-4o-transcribe (best quality)"
        case .whisper: return "whisper-1 (no prompt following)"
        }
    }

    // USD per minute of audio. Output text tokens cost extra but are
    // negligible (<100 tokens/transcription). Update if OpenAI pricing changes.
    var usdPerMinute: Double {
        switch self {
        case .mini: return 0.003
        case .full: return 0.006
        case .whisper: return 0.006
        }
    }
}

public enum MeetingProvider: String, CaseIterable, Sendable {
    case deepgram
    case openai

    public var displayName: String {
        switch self {
        case .deepgram: return "Deepgram Nova-3 (diarized speakers)"
        case .openai:   return "OpenAI Whisper (You/Other only)"
        }
    }
}

enum MeetingCaptureBackend: String, CaseIterable, Sendable {
    /// macOS 13+ ScreenCaptureKit system-audio tap. Implementation deferred to M2.
    case systemAudio = "systemAudio"

    var displayName: String {
        switch self {
        case .systemAudio: return "System audio (ScreenCaptureKit)"
        }
    }
}

public enum DictationHistoryRetention: String, CaseIterable, Sendable {
    case forever
    case year
    case ninetyDays
    case thirtyDays

    public var displayName: String {
        switch self {
        case .forever:    return "Forever"
        case .year:       return "1 year"
        case .ninetyDays: return "90 days"
        case .thirtyDays: return "30 days"
        }
    }
}

/// Retention for raw audio files (dictation WAVs + meeting m4a). Transcripts
/// are kept indefinitely regardless; only the heavy audio is purged.
public enum AudioRetention: String, CaseIterable, Sendable {
    case forever
    case oneYear
    case threeMonths
    case oneMonth
    case sevenDays

    public var displayName: String {
        switch self {
        case .forever:      return "Forever"
        case .oneYear:      return "1 year"
        case .threeMonths:  return "3 months"
        case .oneMonth:     return "1 month"
        case .sevenDays:    return "7 days"
        }
    }

    /// Cutoff date relative to `now`. `nil` means never purge.
    public func cutoffDate(now: Date = Date()) -> Date? {
        switch self {
        case .forever:      return nil
        case .oneYear:      return now.addingTimeInterval(-365 * 86400)
        case .threeMonths:  return now.addingTimeInterval(-90 * 86400)
        case .oneMonth:     return now.addingTimeInterval(-30 * 86400)
        case .sevenDays:    return now.addingTimeInterval(-7 * 86400)
        }
    }
}

public enum ModeOverride: String, CaseIterable, Sendable {
    case auto      // ContextDetector decides (terminal apps → command, others → prose)
    case prose     // always prose
    case command   // always command

    public var displayName: String {
        switch self {
        case .auto:    return "Auto (detect by app)"
        case .prose:   return "Always prose"
        case .command: return "Always command"
        }
    }

    public func next() -> ModeOverride {
        switch self {
        case .auto:    return .prose
        case .prose:   return .command
        case .command: return .auto
        }
    }
}

enum AppSettings {
    private static let keepKey = "keepTranscriptionOnClipboard"
    private static let modelKey = "transcriptionModel"
    private static let forceProseKey = "forceProseMode"   // legacy — read for migration only
    private static let modeOverrideKey = "modeOverride"
    private static let smartCleanupKey = "smartCleanupEnabled"
    private static let meetingModeKey = "meetingModeEnabled"
    private static let meetingConsentKey = "meetingConsentAcknowledged"
    private static let meetingBackendKey = "meetingCaptureBackend"
    private static let meetingRetainAudioKey = "meetingRetainAudio"
    private static let autoShowMeetingPanelKey = "autoShowMeetingPanel"
    private static let meetingSummaryEnabledKey = "meetingSummaryEnabled"
    private static let meetingProviderKey = "meetingProvider"

    static var keepTranscriptionOnClipboard: Bool {
        get { UserDefaults.standard.bool(forKey: keepKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepKey) }
    }

    static var transcriptionModel: TranscriptionModel {
        get {
            if let raw = UserDefaults.standard.string(forKey: modelKey),
               let m = TranscriptionModel(rawValue: raw) {
                return m
            }
            return .mini
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modelKey) }
    }

    static var modeOverride: ModeOverride {
        get {
            // Read new key first; fall back to legacy forceProseMode bool for migration.
            if let raw = UserDefaults.standard.string(forKey: modeOverrideKey),
               let m = ModeOverride(rawValue: raw) {
                return m
            }
            // Legacy migration: forceProseMode=true → .prose; absent or false → .auto.
            // command override is new and has no legacy equivalent.
            if UserDefaults.standard.bool(forKey: forceProseKey) {
                return .prose
            }
            return .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeOverrideKey) }
    }

    static var smartCleanupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: smartCleanupKey) }
        set { UserDefaults.standard.set(newValue, forKey: smartCleanupKey) }
    }

    static var meetingModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: meetingModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: meetingModeKey) }
    }

    static var meetingConsentAcknowledged: Bool {
        get { UserDefaults.standard.bool(forKey: meetingConsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: meetingConsentKey) }
    }

    static var meetingCaptureBackend: MeetingCaptureBackend {
        get {
            if let raw = UserDefaults.standard.string(forKey: meetingBackendKey),
               let b = MeetingCaptureBackend(rawValue: raw) {
                return b
            }
            return .systemAudio
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: meetingBackendKey) }
    }

    static var meetingRetainAudio: Bool {
        get { UserDefaults.standard.bool(forKey: meetingRetainAudioKey) }
        set { UserDefaults.standard.set(newValue, forKey: meetingRetainAudioKey) }
    }

    /// Auto-show the floating Meeting panel when a known meeting app
    /// (Teams, Zoom, Meet, Webex, Slack huddle, etc.) starts a call.
    /// Default OFF — user opts in. Recording is never auto-started.
    static var autoShowMeetingPanel: Bool {
        get { UserDefaults.standard.bool(forKey: autoShowMeetingPanelKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: autoShowMeetingPanelKey)
            NotificationCenter.default.post(name: .autoShowMeetingPanelChanged, object: nil)
        }
    }

    /// Generate an LLM summary of every completed meeting transcript.
    /// Default ON. Cost is ~$0.0005 per meeting on gpt-4o-mini.
    /// Selects the STT provider for meeting transcription.
    /// Smart default: Deepgram if a key is configured, else OpenAI. Once the
    /// user picks explicitly, the choice is honored on subsequent reads.
    static var meetingProvider: MeetingProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: meetingProviderKey),
               let p = MeetingProvider(rawValue: raw) {
                return p
            }
            let hasDeepgram = (KeychainStore(account: "deepgram-api-key").read()?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            return hasDeepgram ? .deepgram : .openai
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: meetingProviderKey) }
    }

    static var meetingSummaryEnabled: Bool {
        get {
            // Default to true on first read so users get summaries by default.
            if UserDefaults.standard.object(forKey: meetingSummaryEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: meetingSummaryEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: meetingSummaryEnabledKey) }
    }

    private static let audioRetentionKey = "audioRetention"

    static var audioRetention: AudioRetention {
        get {
            let raw = UserDefaults.standard.string(forKey: audioRetentionKey)
            return raw.flatMap(AudioRetention.init(rawValue:)) ?? .oneMonth
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: audioRetentionKey) }
    }

    private static let dictationHistoryRetentionKey = "dictationHistoryRetention"

    static var dictationHistoryRetention: DictationHistoryRetention {
        get {
            let raw = UserDefaults.standard.string(forKey: dictationHistoryRetentionKey)
            return raw.flatMap(DictationHistoryRetention.init(rawValue:)) ?? .forever
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dictationHistoryRetentionKey) }
    }

    private static let recordHotkeyKey = "recordHotkey"
    private static let modeToggleHotkeyKey = "modeToggleHotkey"
    private static let pasteHotkeyKey = "pasteHotkey"
    private static let meetingHotkeyKey = "meetingHotkey"
    private static let pasteLastHotkeyKey = "pasteLastHotkey"

    static var recordHotkey: Hotkey {
        get { readHotkey(forKey: recordHotkeyKey) ?? .defaultRecord }
        set {
            writeHotkey(newValue, forKey: recordHotkeyKey)
            NotificationCenter.default.post(name: .recordHotkeyChanged, object: nil)
        }
    }

    static var modeToggleHotkey: Hotkey {
        get { readHotkey(forKey: modeToggleHotkeyKey) ?? .defaultModeToggle }
        set {
            writeHotkey(newValue, forKey: modeToggleHotkeyKey)
            NotificationCenter.default.post(name: .modeToggleHotkeyChanged, object: nil)
        }
    }

    static var pasteHotkey: Hotkey {
        get { readHotkey(forKey: pasteHotkeyKey) ?? .defaultPaste }
        set { writeHotkey(newValue, forKey: pasteHotkeyKey) }
    }

    static var meetingHotkey: Hotkey {
        get { readHotkey(forKey: meetingHotkeyKey) ?? .defaultMeeting }
        set {
            writeHotkey(newValue, forKey: meetingHotkeyKey)
            NotificationCenter.default.post(name: .meetingHotkeyChanged, object: nil)
        }
    }

    static var pasteLastHotkey: Hotkey {
        get { readHotkey(forKey: pasteLastHotkeyKey) ?? .defaultPasteLast }
        set {
            writeHotkey(newValue, forKey: pasteLastHotkeyKey)
            NotificationCenter.default.post(name: .pasteLastHotkeyChanged, object: nil)
        }
    }

    private static func readHotkey(forKey key: String) -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private static func writeHotkey(_ h: Hotkey, forKey key: String) {
        if let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension Notification.Name {
    static let recordHotkeyChanged = Notification.Name("vox.recordHotkeyChanged")
    static let modeToggleHotkeyChanged = Notification.Name("vox.modeToggleHotkeyChanged")
    static let meetingModeChanged = Notification.Name("vox.meetingModeChanged")
    static let meetingHotkeyChanged = Notification.Name("vox.meetingHotkeyChanged")
    static let pasteLastHotkeyChanged = Notification.Name("vox.pasteLastHotkeyChanged")
    static let autoShowMeetingPanelChanged = Notification.Name("vox.autoShowMeetingPanelChanged")
}
