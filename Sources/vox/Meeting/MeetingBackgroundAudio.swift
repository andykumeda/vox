import SoundAnalysis

/// Used only after a successful microphone request returned no segments.
final class MeetingBackgroundAudio: NSObject, SNResultsObserving {
    private var completed = false
    private var windows = 0
    private var possibleSpeech = false
    private var previousSpeechLeader = false

    var matchesBackground: Bool { completed && windows > 0 && !possibleSpeech }

    static func matches(_ url: URL) -> Bool {
        do {
            let analyzer = try SNAudioFileAnalyzer(url: url)
            let observer = MeetingBackgroundAudio()
            try analyzer.add(SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: observer)
            analyzer.analyze()
            return observer.matchesBackground
        } catch {
            return false
        }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        let classification = result as? SNClassificationResult
        observe(speech: classification?.classification(forIdentifier: "speech")?.confidence,
                leader: classification?.classifications.first?.identifier)
    }

    func observe(speech: Double?, leader: String?) {
        windows += 1
        guard let speech, (0...1).contains(speech), let leader else {
            possibleSpeech = true
            return
        }
        // Overlapping windows corroborate a weak speech label. A strong single window is enough.
        let speechLeads = speech >= 0.1 && leader == "speech"
        if speech >= 0.5 || (speechLeads && previousSpeechLeader) { possibleSpeech = true }
        previousSpeechLeader = speechLeads
    }

    func requestDidComplete(_ request: SNRequest) { completed = true }
    func request(_ request: SNRequest, didFailWithError error: Error) { possibleSpeech = true }
}
