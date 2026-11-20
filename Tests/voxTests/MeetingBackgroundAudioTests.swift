import SoundAnalysis
import XCTest
@testable import vox

final class MeetingBackgroundAudioTests: XCTestCase {
    func testOnlyStrongOrCorroboratedSpeechRequiresReview() throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        func matches(_ windows: [(Double?, String?)]) -> Bool {
            let observer = MeetingBackgroundAudio()
            for (score, leader) in windows { observer.observe(speech: score, leader: leader) }
            XCTAssertFalse(observer.matchesBackground)
            observer.requestDidComplete(request)
            return observer.matchesBackground
        }
        XCTAssertTrue(matches([(0.2, "fan"), (0.27, "speech"), (0.2, "fan"), (0.27, "speech")]))
        XCTAssertFalse(matches([(0.2, "speech"), (0.18, "speech")]))
        XCTAssertFalse(matches([(0.5, "speech")]))
        XCTAssertFalse(matches([(nil, "fan")]))
        XCTAssertFalse(matches([(0.01, nil)]))
        XCTAssertFalse(matches([]))
    }
}
