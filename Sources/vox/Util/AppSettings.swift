import Foundation

enum TranscriptionModel: String, CaseIterable, Sendable {
    case mini = "gpt-4o-mini-transcribe"
    case full = "gpt-4o-transcribe"
    case whisper = "whisper-1"

    static let defaultModel: TranscriptionModel = .full

    var displayName: String {
        switch self {
        case .mini: return "gpt-4o-mini-transcribe (lower cost)"
        case .full: return "gpt-4o-transcribe (default, best quality)"
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

    // USD per hour of audio. Deepgram Nova-3 pay-as-you-go = $0.0043/min
    // (~$0.258/hr) with diarization included. OpenAI whisper-1 = $0.006/min
    // (~$0.36/hr). Meetings transcribe both mic + system audio streams,
    // so real billed time is ~2× the wall-clock meeting length.
    public var usdPerHour: Double {
        switch self {
        case .deepgram: return 0.258
        case .openai:   return 0.36
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
    private static let remoteControlModeKey = "remoteControlModeEnabled"
    private static let ignoreRecordHotkeyKey = "ignoreRecordHotkey"
    private static let modelKey = "transcriptionModel"
    private static let forceProseKey = "forceProseMode"   // legacy — read for migration only
    private static let modeOverrideKey = "modeOverride"
    private static let smartCleanupKey = "smartCleanupEnabled"
    private static let meetingModeKey = "meetingModeEnabled"
    private static let meetingConsentKey = "meetingConsentAcknowledged"
    private static let autoShowMeetingPanelKey = "autoShowMeetingPanel"
    private static let meetingSummaryEnabledKey = "meetingSummaryEnabled"
    private static let meetingProviderKey = "meetingProvider"

    // Defaults to true. Restoring the prior clipboard ~1.5s after ⌘V races
    // web text inputs (Comet/Perplexity sidebar, Slack web, etc.) that read
    // the pasteboard asynchronously after the paste event — the restore lands
    // first and the app reads the prior clipboard contents instead of the
    // transcript. Keeping the transcript on the clipboard sidesteps the race;
    // users who want auto-restore can opt out in Settings.
    static var keepTranscriptionOnClipboard: Bool {
        get {
            if let stored = UserDefaults.standard.object(forKey: keepKey) as? Bool {
                return stored
            }
            return true
        }
        set { UserDefaults.standard.set(newValue, forKey: keepKey) }
    }

    static var remoteControlModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: remoteControlModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: remoteControlModeKey) }
    }

    static var ignoreRecordHotkey: Bool {
        get { UserDefaults.standard.bool(forKey: ignoreRecordHotkeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreRecordHotkeyKey) }
    }

    static var transcriptionModel: TranscriptionModel {
        get {
            if let raw = UserDefaults.standard.string(forKey: modelKey),
               let m = TranscriptionModel(rawValue: raw) {
                return m
            }
            return TranscriptionModel.defaultModel
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

    private static let dictationHistoryRetentionKey = "dictationHistoryRetention"

    static var dictationHistoryRetention: DictationHistoryRetention {
        get {
            let raw = UserDefaults.standard.string(forKey: dictationHistoryRetentionKey)
            return raw.flatMap(DictationHistoryRetention.init(rawValue:)) ?? .forever
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dictationHistoryRetentionKey) }
    }

    private static let startSoundKey = "startSound"
    private static let stopSoundKey = "stopSound"
    private static let errorSoundKey = "errorSound"

    static var startSound: SystemAlertSound {
        get { readSound(forKey: startSoundKey) ?? .startDefault }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: startSoundKey) }
    }

    static var stopSound: SystemAlertSound {
        get { readSound(forKey: stopSoundKey) ?? .stopDefault }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: stopSoundKey) }
    }

    static var errorSound: SystemAlertSound {
        get { readSound(forKey: errorSoundKey) ?? .errorDefault }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: errorSoundKey) }
    }

    static func sound(for cue: SoundCue) -> SystemAlertSound {
        switch cue {
        case .start: return startSound
        case .stop: return stopSound
        case .error: return errorSound
        }
    }

    private static func readSound(forKey key: String) -> SystemAlertSound? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return SystemAlertSound(rawValue: raw)
    }

    private static let recordHotkeyKey = "recordHotkey"
    private static let modeToggleHotkeyKey = "modeToggleHotkey"
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
