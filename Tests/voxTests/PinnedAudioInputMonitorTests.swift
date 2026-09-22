import CoreAudio
import XCTest
@testable import vox

final class PinnedAudioInputMonitorTests: XCTestCase {
    func testRouteChangeRestoresPinnedDeviceAfterDebounce() {
        var currentDefault: AudioDeviceID = 7
        var restoredIDs: [AudioDeviceID] = []
        var scheduledWork: (() -> Void)?
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "usb-mic-uid" },
            resolveDevice: { $0 == "usb-mic-uid" ? 42 : nil },
            currentDefault: { currentDefault },
            setDefault: { id in
                restoredIDs.append(id)
                currentDefault = id
                return true
            },
            schedule: { _, work in scheduledWork = work },
            log: { _ in }
        )

        monitor.start()
        restoredIDs.removeAll()
        currentDefault = 7
        monitor.audioHardwareChanged(reason: "default input changed")
        scheduledWork?()

        XCTAssertEqual(restoredIDs, [42])
        XCTAssertEqual(currentDefault, 42)
    }

    func testRouteChangeDoesNotRewriteAnAlreadyPinnedDefault() {
        var setAttempts = 0
        var scheduledWork: (() -> Void)?
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "usb-mic-uid" },
            resolveDevice: { _ in 42 },
            currentDefault: { 42 },
            setDefault: { _ in
                setAttempts += 1
                return true
            },
            schedule: { _, work in scheduledWork = work },
            log: { _ in }
        )

        monitor.start()
        monitor.audioHardwareChanged(reason: "default input changed")
        scheduledWork?()

        XCTAssertEqual(setAttempts, 0)
    }

    func testUnavailablePinnedDeviceNeverFallsBack() {
        var setAttempts = 0
        var scheduledWork: (() -> Void)?
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "missing-usb-mic" },
            resolveDevice: { _ in nil },
            currentDefault: { 7 },
            setDefault: { _ in
                setAttempts += 1
                return true
            },
            schedule: { _, work in scheduledWork = work },
            log: { _ in }
        )

        monitor.start()
        monitor.audioHardwareChanged(reason: "audio device list changed")
        scheduledWork?()

        XCTAssertEqual(setAttempts, 0)
    }

    func testLatestRouteEventSupersedesOlderScheduledRepair() {
        var setAttempts = 0
        var scheduledWork: [() -> Void] = []
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "usb-mic-uid" },
            resolveDevice: { _ in 42 },
            currentDefault: { 7 },
            setDefault: { _ in
                setAttempts += 1
                return true
            },
            schedule: { _, work in scheduledWork.append(work) },
            log: { _ in }
        )

        monitor.start()
        setAttempts = 0
        monitor.audioHardwareChanged(reason: "first event")
        monitor.audioHardwareChanged(reason: "second event")
        XCTAssertEqual(scheduledWork.count, 2)

        scheduledWork[0]()
        scheduledWork[1]()

        XCTAssertEqual(setAttempts, 1)
    }

    func testRouteRepairRetriesWhenCoreAudioInitiallyRejectsPinnedDevice() {
        var currentDefault: AudioDeviceID = 42
        var setAttempts = 0
        var scheduledWork: [() -> Void] = []
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "usb-mic-uid" },
            resolveDevice: { _ in 42 },
            currentDefault: { currentDefault },
            setDefault: { id in
                setAttempts += 1
                guard setAttempts > 1 else { return false }
                currentDefault = id
                return true
            },
            schedule: { _, work in scheduledWork.append(work) },
            log: { _ in }
        )

        monitor.start()
        currentDefault = 7
        monitor.audioHardwareChanged(reason: "default input changed")
        XCTAssertEqual(scheduledWork.count, 1)

        scheduledWork[0]()
        XCTAssertEqual(scheduledWork.count, 2)
        scheduledWork[1]()

        XCTAssertEqual(setAttempts, 2)
        XCTAssertEqual(currentDefault, 42)
    }
}
