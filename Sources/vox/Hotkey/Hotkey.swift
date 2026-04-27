import Foundation
import Carbon.HIToolbox

public struct Hotkey: Codable, Equatable, Sendable {
    public var key: Key
    public var modifiers: Set<Modifier>
    public var triggerMode: TriggerMode
    public var enabled: Bool

    public init(key: Key, modifiers: Set<Modifier>, triggerMode: TriggerMode, enabled: Bool) {
        self.key = key
        self.modifiers = modifiers
        self.triggerMode = triggerMode
        self.enabled = enabled
    }

    public var isValid: Bool {
        switch key {
        case .fn:
            return modifiers.isEmpty
        case .keycode:
            return !modifiers.isEmpty
        }
    }

    /// Conflict semantics: same (key, modifiers), regardless of trigger or enabled.
    /// Disabled bindings never conflict.
    public static func conflict(_ a: Hotkey, _ b: Hotkey) -> Bool {
        guard a.enabled, b.enabled else { return false }
        return a.key == b.key && a.modifiers == b.modifiers
    }
}

public enum Key: Codable, Equatable, Sendable {
    case fn
    case keycode(UInt16)
}

public enum Modifier: String, Codable, CaseIterable, Sendable {
    case command
    case control
    case option
    case shift
}

public enum TriggerMode: String, Codable, Sendable {
    case pressHold
    case tapToggle
}

public extension Hotkey {
    static let defaultRecord = Hotkey(
        key: .fn,
        modifiers: [],
        triggerMode: .pressHold,
        enabled: true
    )

    static let defaultModeToggle = Hotkey(
        key: .keycode(UInt16(kVK_ANSI_M)),
        modifiers: [.control, .option],
        triggerMode: .tapToggle,
        enabled: true
    )

    static let defaultPaste = Hotkey(
        key: .keycode(UInt16(kVK_ANSI_V)),
        modifiers: [.command],
        triggerMode: .tapToggle,
        enabled: true
    )
}
