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

enum MeetingCaptureBackend: String, CaseIterable, Sendable {
    /// macOS 13+ ScreenCaptureKit system-audio tap. Implementation deferred to M2.
    case systemAudio = "systemAudio"

    var displayName: String {
        switch self {
        case .systemAudio: return "System audio (ScreenCaptureKit)"
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

    private static let recordHotkeyKey = "recordHotkey"
    private static let modeToggleHotkeyKey = "modeToggleHotkey"
    private static let pasteHotkeyKey = "pasteHotkey"

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
}
