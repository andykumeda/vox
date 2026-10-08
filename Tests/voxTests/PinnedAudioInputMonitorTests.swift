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

    func testUnavailablePinnedDeviceFailsWhenNoBuiltInMicExists() {
        var setAttempts = 0
        var scheduledWork: (() -> Void)?
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "missing-usb-mic" },
            builtInMicrophoneUID: { nil },
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

    func testDisconnectFallsBackAndReconnectRestoresPreferredWithoutChangingSelection() {
        var preferredPresent = false
        var current: AudioDeviceID = 7
        var changes: [Bool] = []
        var scheduled: (() -> Void)?
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "usb-mic" },
            builtInMicrophoneUID: { "built-in" },
            resolveDevice: { uid in
                if uid == "built-in" { return 9 }
                return preferredPresent ? 42 : nil
            },
            currentDefault: { current },
            setDefault: { current = $0; return true },
            schedule: { _, work in scheduled = work },
            log: { _ in }
        )
        monitor.onFallbackChanged = { changes.append($0) }
        monitor.start()
        XCTAssertEqual(current, 9)
        XCTAssertTrue(monitor.isUsingBuiltInFallback)
        monitor.reassertPinnedInput(reason: "recording")
        XCTAssertEqual(changes, [true])

        preferredPresent = true
        monitor.audioHardwareChanged(reason: "reconnect")
        scheduled?()
        XCTAssertEqual(current, 42)
        XCTAssertFalse(monitor.isUsingBuiltInFallback)
        XCTAssertEqual(changes, [true, false])
    }

    func testEveryReconciliationNotifiesDeviceListEvenIfFallbackStateIsUnchanged() {
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { "absent" },
            builtInMicrophoneUID: { "built-in" },
            resolveDevice: { $0 == "built-in" ? 9 : nil },
            currentDefault: { 9 },
            log: { _ in }
        )
        let notifications = expectation(description: "settings refresh notifications")
        notifications.expectedFulfillmentCount = 2
        let token = NotificationCenter.default.addObserver(
            forName: .audioInputDevicesChanged, object: monitor, queue: nil
        ) { _ in notifications.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }
        monitor.reassertPinnedInput(reason: "disconnect")
        monitor.reassertPinnedInput(reason: "second device change")
        wait(for: [notifications], timeout: 0.1)
        XCTAssertTrue(monitor.isUsingBuiltInFallback)
    }

    func testSystemDefaultDoesNotForceBuiltInMicrophone() {
        var attempts = 0
        let monitor = PinnedAudioInputMonitor(
            selectedUID: { nil },
            builtInMicrophoneUID: { "built-in" },
            resolveDevice: { _ in 9 },
            currentDefault: { 7 },
            setDefault: { _ in attempts += 1; return true },
            log: { _ in }
        )
        XCTAssertNil(monitor.reassertPinnedInput(reason: "test"))
        XCTAssertEqual(attempts, 0)
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
