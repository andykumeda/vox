import SoundAnalysis

/// Used only after a successful microphone request returned no segments.
final class MeetingBackgroundAudio: NSObject, SNResultsObserving {
    private var completed = false
    private var windows = 0
    private var possibleSpeech = false

    static func matches(_ url: URL) -> Bool {
        do {
            let analyzer = try SNAudioFileAnalyzer(url: url)
            let observer = MeetingBackgroundAudio()
            try analyzer.add(SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: observer)
            analyzer.analyze()
            return observer.completed && observer.windows > 0 && !observer.possibleSpeech
        } catch {
            return false
        }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        windows += 1
        let confidence = (result as? SNClassificationResult)?.classification(forIdentifier: "speech")?.confidence
        if !(confidence.map { $0 < 0.1 } ?? false) { possibleSpeech = true }
    }

    func requestDidComplete(_ request: SNRequest) { completed = true }
    func request(_ request: SNRequest, didFailWithError error: Error) { possibleSpeech = true }
}
