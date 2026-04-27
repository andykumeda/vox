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

enum AppSettings {
    private static let keepKey = "keepTranscriptionOnClipboard"
    private static let modelKey = "transcriptionModel"
    private static let forceProseKey = "forceProseMode"

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

    static var forceProseMode: Bool {
        get { UserDefaults.standard.bool(forKey: forceProseKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceProseKey) }
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
