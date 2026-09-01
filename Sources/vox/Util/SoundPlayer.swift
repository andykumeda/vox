import AppKit

public enum SoundCue: String {
    case start = "Tink"
    case stop = "Pop"
    case error = "Funk"
}

public final class SoundPlayer {
    private var activeSound: NSSound?

    public init() {}

    public func play(_ cue: SoundCue) {
        activeSound?.stop()
        guard let sound = NSSound(named: NSSound.Name(cue.rawValue)) else {
            NSSound.beep()
            return
        }
        activeSound = sound
        sound.play()
    }
}
