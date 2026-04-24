import AppKit

public enum SoundCue: String {
    case start = "Tink"
    case stop = "Pop"
    case error = "Funk"
}

public struct SoundPlayer {
    public init() {}

    public func play(_ cue: SoundCue) {
        NSSound(named: NSSound.Name(cue.rawValue))?.play()
    }
}
