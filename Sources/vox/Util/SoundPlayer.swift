import AppKit

/// Built-in macOS alert sounds from `/System/Library/Sounds`, plus a silent option.
public enum SystemAlertSound: String, CaseIterable, Sendable, Identifiable {
    case none
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    public var id: String { rawValue }

    public var displayName: String {
        self == .none ? "None" : rawValue
    }

    public var fileURL: URL? {
        guard self != .none else { return nil }
        return URL(fileURLWithPath: "/System/Library/Sounds/\(rawValue).aiff")
    }

    public static let startDefault: SystemAlertSound = .tink
    public static let stopDefault: SystemAlertSound = .pop
    public static let errorDefault: SystemAlertSound = .funk
}

public enum SoundCue: String, CaseIterable, Sendable {
    case start
    case stop
    case error

    public var defaultSound: SystemAlertSound {
        switch self {
        case .start: return .startDefault
        case .stop: return .stopDefault
        case .error: return .errorDefault
        }
    }
}

public final class SoundPlayer {
    public static let shared = SoundPlayer()

    private var activeSound: NSSound?

    public init() {}

    public func play(_ cue: SoundCue) {
        play(AppSettings.sound(for: cue))
    }

    public func play(_ sound: SystemAlertSound) {
        play(named: sound.rawValue)
    }

    /// Start cues are muted for the whole time the mic is open. Callers must
    /// play the start sound, then open capture — never the reverse.
    static func playStartCueThenOpenCapture(
        playStart: () -> Void,
        openCapture: () throws -> Void
    ) rethrows {
        playStart()
        try openCapture()
    }

    func play(named name: String) {
        activeSound?.stop()
        activeSound = nil
        guard name != SystemAlertSound.none.rawValue, !name.isEmpty else { return }
        guard let sound = Self.loadSound(named: name) else {
            dlog("sound name=\(name) missing; falling back to system beep")
            NSSound.beep()
            return
        }
        activeSound = sound
        let started = sound.play()
        if !started {
            dlog("sound name=\(name) play() returned false; falling back to system beep")
            NSSound.beep()
        }
    }

    /// Independent instance from the system sound file. `NSSound(named:)` returns a
    /// shared cached object; stopping it to play the next cue can leave later plays
    /// inaudible even when `play()` returns true.
    static func loadSound(named name: String) -> NSSound? {
        guard name != SystemAlertSound.none.rawValue, !name.isEmpty else { return nil }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        if FileManager.default.fileExists(atPath: url.path),
           let fromFile = NSSound(contentsOf: url, byReference: true) {
            return fromFile
        }
        return (NSSound(named: NSSound.Name(name))?.copy() as? NSSound)
    }
}
