import Foundation

enum AppSettings {
    private static let keepKey = "keepTranscriptionOnClipboard"

    static var keepTranscriptionOnClipboard: Bool {
        get { UserDefaults.standard.bool(forKey: keepKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepKey) }
    }
}
