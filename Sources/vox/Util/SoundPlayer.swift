import AppKit
import AVFoundation

protocol SoundControlling: AnyObject {
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
}

extension AVAudioPlayer: SoundControlling {}

private final class NSSoundAdapter: SoundControlling {
    private let sound: NSSound

    init(_ sound: NSSound) {
        self.sound = sound
    }

    func prepareToPlay() -> Bool { true }
    func play() -> Bool { sound.play() }
    func stop() { _ = sound.stop() }
}

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

public final class SoundPlayer: @unchecked Sendable {
    public static let shared = SoundPlayer()

    private let lock = NSLock()
    private let loader: (String) -> SoundControlling?
    private let fallbackBeep: () -> Void
    private var activeSound: SoundControlling?
    private var preparedSounds: [String: SoundControlling] = [:]

    public convenience init() {
        self.init(
            loader: { Self.loadSound(named: $0) },
            fallbackBeep: { NSSound.beep() }
        )
    }

    init(
        loader: @escaping (String) -> SoundControlling?,
        fallbackBeep: @escaping () -> Void
    ) {
        self.loader = loader
        self.fallbackBeep = fallbackBeep
    }

    public func play(_ cue: SoundCue) {
        play(AppSettings.sound(for: cue))
    }

    public func play(_ sound: SystemAlertSound) {
        play(named: sound.rawValue)
    }

    /// Prime the selected cue without playing it. Bluetooth output can take
    /// several seconds to wake on the first NSSound call after launch; doing
    /// that work on a utility queue keeps the first Fn press responsive.
    public func prepare(_ sound: SystemAlertSound) {
        let name = sound.rawValue
        guard name != SystemAlertSound.none.rawValue, !name.isEmpty else { return }

        lock.lock()
        let alreadyPrepared = preparedSounds[name] != nil
        lock.unlock()
        guard !alreadyPrepared, let prepared = loader(name) else { return }

        let startedAt = Date()
        let ready = prepared.prepareToPlay()
        let elapsed = Date().timeIntervalSince(startedAt)
        dlog("sound prepare name=\(name) ready=\(ready) elapsed=\(String(format: "%.3f", elapsed))s")
        guard ready else { return }

        lock.lock()
        if preparedSounds[name] == nil {
            preparedSounds[name] = prepared
        }
        lock.unlock()
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
        lock.lock()
        let previous = activeSound
        activeSound = nil
        let prepared = preparedSounds.removeValue(forKey: name)
        lock.unlock()

        previous?.stop()
        guard name != SystemAlertSound.none.rawValue, !name.isEmpty else { return }
        guard let sound = prepared ?? loader(name) else {
            dlog("sound name=\(name) missing; falling back to system beep")
            fallbackBeep()
            return
        }

        lock.lock()
        activeSound = sound
        lock.unlock()

        let startedAt = Date()
        let started = sound.play()
        let elapsed = Date().timeIntervalSince(startedAt)
        dlog("sound play name=\(name) prepared=\(prepared != nil) elapsed=\(String(format: "%.3f", elapsed))s")
        if !started {
            dlog("sound name=\(name) play() returned false; falling back to system beep")
            fallbackBeep()
        }
    }

    /// Independent instance from the system sound file. `NSSound(named:)` returns a
    /// shared cached object; stopping it to play the next cue can leave later plays
    /// inaudible even when `play()` returns true.
    static func loadSound(named name: String) -> SoundControlling? {
        guard name != SystemAlertSound.none.rawValue, !name.isEmpty else { return nil }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        if FileManager.default.fileExists(atPath: url.path),
           let fromFile = try? AVAudioPlayer(contentsOf: url) {
            return fromFile
        }
        guard let named = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else {
            return nil
        }
        return NSSoundAdapter(named)
    }
}
