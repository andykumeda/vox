import CoreAudio
import Foundation

/// Keeps the user's pinned microphone as macOS's default input even when an
/// output-route transition activates a Bluetooth hands-free input behind it.
/// AudioRecorder still binds the same UID before capture; this monitor closes
/// the gap between route changes and the next recording attempt.
final class PinnedAudioInputMonitor {
    static let shared = PinnedAudioInputMonitor()

    typealias SelectedUID = () -> String?
    typealias ResolveDevice = (String) -> AudioDeviceID?
    typealias CurrentDefault = () -> AudioDeviceID?
    typealias SetDefault = (AudioDeviceID) -> Bool
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    typealias Log = (String) -> Void

    private let selectedUID: SelectedUID
    private let resolveDevice: ResolveDevice
    private let currentDefault: CurrentDefault
    private let setDefault: SetDefault
    private let schedule: Schedule
    private let log: Log

    private var isMonitoring = false
    private var repairGeneration = 0
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private static let repairDelays: [TimeInterval] = [0.05, 0.15, 0.50]

    init(
        selectedUID: @escaping SelectedUID = { AppSettings.audioInputDeviceUID },
        resolveDevice: @escaping ResolveDevice = { AudioInputDevices.deviceID(forUID: $0) },
        currentDefault: @escaping CurrentDefault = { AudioInputDevices.defaultInputDeviceID() },
        setDefault: @escaping SetDefault = { AudioInputDevices.setDefaultInputDevice($0) },
        schedule: @escaping Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        log: @escaping Log = { dlog($0) }
    ) {
        self.selectedUID = selectedUID
        self.resolveDevice = resolveDevice
        self.currentDefault = currentDefault
        self.setDefault = setDefault
        self.schedule = schedule
        self.log = log
    }

    deinit {
        stop()
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        defaultInputListener = addListener(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            reason: "default input changed"
        )
        deviceListListener = addListener(
            selector: kAudioHardwarePropertyDevices,
            reason: "audio device list changed"
        )
        reassertPinnedInput(reason: "monitor startup")
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        repairGeneration += 1

        removeListener(
            defaultInputListener,
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        removeListener(
            deviceListListener,
            selector: kAudioHardwarePropertyDevices
        )
        defaultInputListener = nil
        deviceListListener = nil
    }

    /// Core Audio can emit several route notifications while Bluetooth settles.
    /// Debounce them briefly, then retry boundedly because HAL can reject a
    /// selection while Bluetooth settles. Resolve the persistent UID on every
    /// attempt because device IDs can change after a reconnect.
    func audioHardwareChanged(reason: String) {
        repairGeneration += 1
        let generation = repairGeneration
        scheduleRepair(reason: reason, generation: generation, attempt: 0)
    }

    @discardableResult
    func reassertPinnedInput(reason: String) -> Bool? {
        guard let uid = selectedUID() else { return nil }
        guard let pinnedID = resolveDevice(uid) else {
            log("pinned input unavailable after \(reason) uid=\(uid)")
            return false
        }
        if currentDefault() == pinnedID {
            log("pinned input retained after \(reason) uid=\(uid) deviceID=\(pinnedID)")
            return true
        }

        let restored = setDefault(pinnedID)
        log(
            "pinned input restored after \(reason) uid=\(uid) "
                + "deviceID=\(pinnedID) success=\(restored)"
        )
        return restored
    }

    private func addListener(
        selector: AudioObjectPropertySelector,
        reason: String
    ) -> AudioObjectPropertyListenerBlock? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioHardwareChanged(reason: reason)
        }
        let status = AudioObjectAddPropertyListenerBlock(
            system,
            &address,
            DispatchQueue.main,
            listener
        )
        guard status == noErr else {
            log("pinned input monitor listener failed selector=\(selector) status=\(status)")
            return nil
        }
        return listener
    }

    private func scheduleRepair(reason: String, generation: Int, attempt: Int) {
        guard attempt < Self.repairDelays.count else { return }
        schedule(Self.repairDelays[attempt]) { [weak self] in
            guard let self,
                  self.isMonitoring,
                  generation == self.repairGeneration
            else { return }
            let result = self.reassertPinnedInput(reason: reason)
            if result == false {
                self.scheduleRepair(
                    reason: reason,
                    generation: generation,
                    attempt: attempt + 1
                )
            }
        }
    }

    private func removeListener(
        _ listener: AudioObjectPropertyListenerBlock?,
        selector: AudioObjectPropertySelector
    ) {
        guard let listener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
    }
}
