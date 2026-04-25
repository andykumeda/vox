import AppKit
import ApplicationServices

private let logURL: URL = {
    let fm = FileManager.default
    let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
    try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
    return logs.appendingPathComponent("vox.log")
}()

private let logHandle: FileHandle? = {
    let path = logURL.path
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let h = try? FileHandle(forWritingTo: logURL) else { return nil }
    try? h.seekToEnd()
    return h
}()

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

@inline(__always) private func dlog(_ msg: @autoclosure () -> String) {
    let line = "\(isoFormatter.string(from: Date())) [vox] \(msg())\n"
    let data = Data(line.utf8)
    FileHandle.standardError.write(data)
    try? logHandle?.write(contentsOf: data)
}

enum MenuIconState {
    case idle, recording, transcribing, error

    var symbolName: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }
}

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let keychain = KeychainStore()
    private let contextDetector = ContextDetector()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let injector = TextInjector()
    private let sound = SoundPlayer()
    private lazy var transcriber = OpenAITranscriber { [keychain] in keychain.read() }
    private lazy var settingsController = SettingsWindowController(keychain: keychain)

    private var currentMode: TranscriptionMode = .prose
    private var state: MenuIconState = .idle {
        didSet { refreshIcon() }
    }

    func start() {
        configureMenu()
        refreshIcon()

        hotkey.onPress = { [weak self] in
            dlog("Fn press")
            self?.beginRecording()
        }
        hotkey.onRelease = { [weak self] in
            dlog("Fn release")
            self?.endRecordingAndTranscribe()
        }

        Task {
            let granted = await recorder.requestPermission()
            dlog("mic permission granted=\(granted)")
        }

        let hkStarted = hotkey.start()
        dlog("hotkey.start() -> \(hkStarted)")
        if !hkStarted {
            state = .error
            presentAlert(
                title: "Couldn't start hotkey listener",
                message: "Grant Input Monitoring permission in System Settings, then quit and relaunch Vox."
            )
        }

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        dlog("AXIsProcessTrusted=\(trusted)")
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Hold Fn to dictate", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: "Vox")
        image?.isTemplate = (state != .recording)
        button.image = image
        button.toolTip = {
            switch state {
            case .idle: return "Vox — idle"
            case .recording: return "Vox — recording…"
            case .transcribing: return "Vox — transcribing…"
            case .error: return "Vox — error"
            }
        }()
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    // MARK: - Record / Transcribe

    private func beginRecording() {
        guard state == .idle else { return }
        currentMode = contextDetector.modeForFrontmost()
        do {
            try recorder.start()
            state = .recording
            sound.play(.start)
        } catch {
            state = .error
            sound.play(.error)
            NSLog("[vox] recorder.start failed: \(error)")
        }
    }

    private func endRecordingAndTranscribe() {
        guard state == .recording else { return }
        let wav = recorder.stop()
        sound.play(.stop)
        let mode = currentMode

        // Silence gate: skip the transcription API if too short or too quiet.
        // Whisper hallucinates / echoes the system prompt when fed silence.
        let (durationSec, rms) = wavStats(wav)
        dlog("wav bytes=\(wav.count) duration=\(durationSec)s rms=\(rms) mode=\(mode)")
        if durationSec < 0.35 || rms < 150 {
            dlog("silence gate tripped — skipping transcription")
            state = .idle
            return
        }

        state = .transcribing

        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.transcriber.transcribe(wav: wav, mode: mode)
                dlog("raw=\(raw)")
                let processed = PostProcessor(mode: mode).apply(raw)
                dlog("processed=\(processed)")
                await MainActor.run {
                    self.injector.paste(processed, keepOnClipboard: AppSettings.keepTranscriptionOnClipboard)
                    self.state = .idle
                }
            } catch {
                dlog("transcription failed: \(error)")
                await MainActor.run {
                    self.state = .error
                    self.sound.play(.error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.state = .idle
                    }
                }
            }
        }
    }

    private func wavStats(_ wav: Data) -> (durationSec: Double, rms: Double) {
        let headerSize = 44
        guard wav.count > headerSize else { return (0, 0) }
        let pcm = wav.subdata(in: headerSize..<wav.count)
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return (0, 0) }
        let duration = Double(sampleCount) / 16_000.0
        let rms = pcm.withUnsafeBytes { raw -> Double in
            let buf = raw.bindMemory(to: Int16.self)
            var sumSq = 0.0
            for s in buf { sumSq += Double(s) * Double(s) }
            return sqrt(sumSq / Double(buf.count))
        }
        return (duration, rms)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
