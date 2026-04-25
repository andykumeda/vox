import Foundation

public struct UsageTotals: Sendable {
    public let calls: Int
    public let audioSeconds: Double
    public let words: Int
    public let usd: Double
}

enum UsageTracker {
    private static let callsKey = "usage.calls"
    private static let secondsKey = "usage.audioSeconds"
    private static let wordsKey = "usage.words"
    private static let usdKey = "usage.usd"

    static func record(durationSec: Double, wordCount: Int, model: TranscriptionModel) {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: callsKey) + 1, forKey: callsKey)
        d.set(d.double(forKey: secondsKey) + durationSec, forKey: secondsKey)
        d.set(d.integer(forKey: wordsKey) + wordCount, forKey: wordsKey)
        let costThisCall = (durationSec / 60.0) * model.usdPerMinute
        d.set(d.double(forKey: usdKey) + costThisCall, forKey: usdKey)
    }

    static func totals() -> UsageTotals {
        let d = UserDefaults.standard
        return UsageTotals(
            calls: d.integer(forKey: callsKey),
            audioSeconds: d.double(forKey: secondsKey),
            words: d.integer(forKey: wordsKey),
            usd: d.double(forKey: usdKey)
        )
    }

    static func reset() {
        let d = UserDefaults.standard
        d.removeObject(forKey: callsKey)
        d.removeObject(forKey: secondsKey)
        d.removeObject(forKey: wordsKey)
        d.removeObject(forKey: usdKey)
    }

    static func costEstimate(durationSec: Double, model: TranscriptionModel) -> Double {
        return (durationSec / 60.0) * model.usdPerMinute
    }
}
