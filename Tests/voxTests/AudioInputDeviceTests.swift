import CoreAudio
import XCTest
@testable import vox

final class AudioInputDeviceTests: XCTestCase {
    private let savedUID = "AppleUSBAudioEngine:Shenzhen jiayz photo industrial ltd:BOYA mini 2:100000:3"
    private let reconnectedUID = "AppleUSBAudioEngine:Shenzhen jiayz photo industrial ltd:BOYA mini 2:1100000:3"

    private func device(_ uid: String, id: AudioDeviceID = 42, transport: String = "USB") -> AudioInputDevice {
        AudioInputDevice(id: id, uid: uid, name: "BOYA mini 2", transport: transport, isSystemDefault: false)
    }

    func testRecognizesPreferredUSBMicAfterLocationChanges() {
        let reconnected = device(reconnectedUID)
        XCTAssertEqual(AudioInputDevices.preferredDevice(forUID: savedUID, in: [reconnected]), reconnected)
    }

    func testExactUIDWinsEvenWithAnotherIdenticalModelConnected() {
        let exact = device(savedUID, id: 7)
        XCTAssertEqual(AudioInputDevices.preferredDevice(forUID: savedUID, in: [device(reconnectedUID), exact]), exact)
    }

    func testDoesNotGuessBetweenTwoReconnectedDevicesOfSameModel() {
        let other = device("AppleUSBAudioEngine:Shenzhen jiayz photo industrial ltd:BOYA mini 2:2100000:3", id: 43)
        XCTAssertNil(AudioInputDevices.preferredDevice(forUID: savedUID, in: [device(reconnectedUID), other]))
    }

    func testDoesNotMatchDifferentManufacturerModelOrInterface() {
        for uid in [
            "AppleUSBAudioEngine:Other:BOYA mini 2:1100000:3",
            "AppleUSBAudioEngine:Shenzhen jiayz photo industrial ltd:Other:1100000:3",
            "AppleUSBAudioEngine:Shenzhen jiayz photo industrial ltd:BOYA mini 2:1100000:4"
        ] {
            XCTAssertNil(AudioInputDevices.preferredDevice(forUID: savedUID, in: [device(uid)]))
        }
    }

    func testUSBRecoveryNeverMatchesVirtualOrBluetoothInputs() {
        for transport in ["Virtual", "Bluetooth", "Built-in", ""] {
            XCTAssertNil(AudioInputDevices.preferredDevice(forUID: savedUID, in: [device(reconnectedUID, transport: transport)]))
        }
    }

    func testUnsupportedAndMalformedUIDsRequireExactMatch() {
        for uid in ["", "BuiltInMicrophoneDevice", "AppleUSBAudioEngine:Company:Mic::3", "AppleUSBAudioEngine:Company:Mic:location"] {
            XCTAssertNil(AudioInputDevices.preferredDevice(forUID: uid, in: [device(reconnectedUID)]))
        }
        let builtIn = device("BuiltInMicrophoneDevice", transport: "Built-in")
        XCTAssertEqual(AudioInputDevices.preferredDevice(forUID: builtIn.uid, in: [builtIn]), builtIn)
    }

    func testRouteMonitorRestoresChangedUSBUIDAfterBuiltInFallback() {
        var devices = [AudioInputDevice(id: 9, uid: "BuiltInMicrophoneDevice", name: "Built-in", transport: "Built-in", isSystemDefault: true)]
        var current: AudioDeviceID = 9
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { self.savedUID },
            builtInMicrophoneUID: { "BuiltInMicrophoneDevice" },
            resolveDevice: { AudioInputDevices.preferredDevice(forUID: $0, in: devices)?.id },
            currentDefault: { current },
            setDefault: { current = $0; return true },
            log: { _ in }
        )
        XCTAssertEqual(monitor.reassertPinnedInput(reason: "disconnect"), true)
        XCTAssertTrue(monitor.isUsingBuiltInFallback)
        devices.append(device(reconnectedUID))
        XCTAssertEqual(monitor.reassertPinnedInput(reason: "reconnect on another port"), true)
        XCTAssertEqual(current, 42)
        XCTAssertFalse(monitor.isUsingBuiltInFallback)
    }
}
