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
}

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let keychain = KeychainStore()
    private let contextDetector = ContextDetector()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let injector = TextInjector()
    private let sound = SoundPlayer()
    private lazy var transcriber = OpenAITranscriber(
        modelProvider: { AppSettings.transcriptionModel.rawValue },
        apiKeyProvider: { [keychain] in keychain.read() }
    )
    private lazy var settingsController = SettingsWindowController(keychain: keychain)
    private var helpWindowController: HelpWindowController?

    private var currentMode: TranscriptionMode = .prose
    private var pulseTimer: Timer?
    private var state: MenuIconState = .idle {
        didSet { refreshIcon() }
    }

    func start() {
        configureMenu()
        refreshIcon()

        hotkey.onRecordPress = { [weak self] in
            dlog("Fn press")
            self?.beginRecording()
        }
        hotkey.onRecordRelease = { [weak self] in
            dlog("Fn release")
            self?.endRecordingAndTranscribe()
        }
        hotkey.onModeToggle = { [weak self] in
            self?.handleModeToggle()
        }

        NotificationCenter.default.addObserver(
            forName: .recordHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
        NotificationCenter.default.addObserver(
            forName: .modeToggleHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
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
        let helpItem = NSMenuItem(title: "Help…", action: #selector(showHelpAction(_:)), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch state {
        case .idle:
            symbolName = AppSettings.forceProseMode ? "lock.bubble.fill" : "text.bubble"
        case .recording:
            symbolName = "text.bubble.fill"
        case .transcribing:
            symbolName = "text.bubble.fill"
        case .error:
            symbolName = "exclamationmark.triangle"
        }
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Vox")
        switch state {
        case .recording:
            // Palette config bakes the color into the rendered SF Symbol.
            // NSStatusBarButton's contentTintColor is unreliable in the menubar,
            // so apply the color directly to the image.
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let tinted = base?.withSymbolConfiguration(cfg)
            tinted?.isTemplate = false
            button.image = tinted
        case .transcribing:
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            let tinted = base?.withSymbolConfiguration(cfg)
            tinted?.isTemplate = false
            button.image = tinted
        case .idle, .error:
            base?.isTemplate = true
            button.image = base
        }
        button.contentTintColor = nil
        if state == .transcribing {
            startPulsing()
        } else {
            stopPulsing()
        }
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

    public func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        let controller = helpWindowController
        Task { @MainActor in
            controller?.show()
        }
    }

    @objc private func showHelpAction(_ sender: Any?) {
        showHelp()
    }

    private func handleModeToggle() {
        AppSettings.forceProseMode.toggle()
        refreshIcon()
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func reconfigureHotkey() {
        hotkey.stop()
        hotkey.configure(
            record: AppSettings.recordHotkey,
            modeToggle: AppSettings.modeToggleHotkey
        )
        _ = hotkey.start()
    }

    // MARK: - Record / Transcribe

    private func beginRecording() {
        guard state == .idle else { return }
        currentMode = AppSettings.forceProseMode ? .prose : contextDetector.modeForFrontmost()
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
                let processed = await MainActor.run {
                    PostProcessor(mode: mode).process(raw)
                }
                let wordCount = processed.text.split(whereSeparator: { $0.isWhitespace }).count
                let model = AppSettings.transcriptionModel
                let cost = UsageTracker.costEstimate(durationSec: durationSec, model: model)
                UsageTracker.record(durationSec: durationSec, wordCount: wordCount, model: model)
                dlog("processed=\(processed.text) keys=\(processed.suffixKeys) words=\(wordCount) cost=$\(String(format: "%.4f", cost))")
                await MainActor.run {
                    let pasteDelay: Double
                    if processed.text.isEmpty {
                        pasteDelay = 0
                    } else {
                        self.injector.paste(processed.text, keepOnClipboard: AppSettings.keepTranscriptionOnClipboard)
                        pasteDelay = 0.2
                    }
                    for (i, key) in processed.suffixKeys.enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + 0.18 * Double(i)) {
                            self.injector.sendKey(key)
                        }
                    }
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

    private func startPulsing() {
        guard pulseTimer == nil, let button = statusItem.button else { return }
        var dim = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak button] _ in
            guard let button else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                button.animator().alphaValue = dim ? 1.0 : 0.35
            }
            dim.toggle()
        }
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusItem.button?.alphaValue = 1.0
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
