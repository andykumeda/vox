import UIKit
import VoxCore

final class KeyboardViewController: UIInputViewController {
    private let statusLabel = UILabel()
    private let microphoneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var letterButtons: [UIButton] = []
    private var isShifted = false
    private var pollTimer: Timer?
    private var activeRequestID: UUID?
    private var exchangeStore: MobileDictationExchangeStore?
    private let defaults = UserDefaults(suiteName: MobileAppGroup.identifier)
    private let activeRequestKey = "keyboard.activeRequestID"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGray5
        exchangeStore = try? MobileAppGroup.exchangeStore()
        if let persisted = defaults?.string(forKey: activeRequestKey) {
            activeRequestID = UUID(uuidString: persisted)
        }
        buildKeyboard()
        refreshState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func buildKeyboard() {
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        microphoneButton.configuration = .filled()
        microphoneButton.configuration?.image = UIImage(systemName: "mic.fill")
        microphoneButton.configuration?.cornerStyle = .capsule
        microphoneButton.accessibilityLabel = "Start dictation"
        microphoneButton.addTarget(self, action: #selector(microphoneTapped), for: .touchUpInside)

        cancelButton.configuration = .plain()
        cancelButton.configuration?.image = UIImage(systemName: "xmark.circle")
        cancelButton.accessibilityLabel = "Cancel dictation"
        cancelButton.isHidden = true
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let topBar = UIStackView(arrangedSubviews: [statusLabel, cancelButton, microphoneButton])
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 8
        topBar.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        topBar.isLayoutMarginsRelativeArrangement = true

        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 7
        rows.distribution = .fillEqually
        rows.addArrangedSubview(makeLetterRow("qwertyuiop"))
        rows.addArrangedSubview(makeLetterRow("asdfghjkl"))

        let shift = makeSystemButton(title: "⇧", action: #selector(shiftTapped))
        let delete = makeSystemButton(title: "⌫", action: #selector(deleteTapped))
        let thirdLetters = makeLetterRow("zxcvbnm")
        let thirdRow = UIStackView(arrangedSubviews: [shift, thirdLetters, delete])
        thirdRow.axis = .horizontal
        thirdRow.spacing = 6
        thirdRow.distribution = .fillProportionally
        shift.widthAnchor.constraint(equalToConstant: 46).isActive = true
        delete.widthAnchor.constraint(equalToConstant: 46).isActive = true
        rows.addArrangedSubview(thirdRow)

        let globe = makeSystemButton(title: "🌐", action: #selector(globeTapped))
        let comma = makeInsertButton(title: ",", text: ",")
        let space = makeInsertButton(title: "space", text: " ")
        let period = makeInsertButton(title: ".", text: ".")
        let returnButton = makeInsertButton(title: "return", text: "\n")
        let bottomRow = UIStackView(arrangedSubviews: [globe, comma, space, period, returnButton])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 6
        bottomRow.distribution = .fillProportionally
        globe.widthAnchor.constraint(equalToConstant: 46).isActive = true
        comma.widthAnchor.constraint(equalToConstant: 42).isActive = true
        period.widthAnchor.constraint(equalToConstant: 42).isActive = true
        returnButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        rows.addArrangedSubview(bottomRow)

        let root = UIStackView(arrangedSubviews: [topBar, rows])
        root.axis = .vertical
        root.spacing = 4
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            view.heightAnchor.constraint(equalToConstant: 288),
            topBar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func makeLetterRow(_ letters: String) -> UIStackView {
        let buttons = letters.map { character -> UIButton in
            let button = UIButton(type: .system)
            button.configuration = keyConfiguration(title: String(character))
            button.accessibilityLabel = String(character)
            button.addTarget(self, action: #selector(letterTapped(_:)), for: .touchUpInside)
            letterButtons.append(button)
            return button
        }
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fillEqually
        return row
    }

    private func makeSystemButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = keyConfiguration(title: title, color: .systemGray3)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeInsertButton(title: String, text: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = keyConfiguration(title: title)
        button.accessibilityHint = text
        button.addTarget(self, action: #selector(insertButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    private func keyConfiguration(title: String, color: UIColor = .systemBackground) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)
        return configuration
    }

    @objc private func letterTapped(_ sender: UIButton) {
        guard let title = sender.configuration?.title else { return }
        textDocumentProxy.insertText(isShifted ? title.uppercased() : title.lowercased())
        if isShifted {
            isShifted = false
            updateLetterCase()
        }
    }

    @objc private func insertButtonTapped(_ sender: UIButton) {
        guard let text = sender.accessibilityHint else { return }
        textDocumentProxy.insertText(text)
    }

    @objc private func shiftTapped() {
        isShifted.toggle()
        updateLetterCase()
    }

    @objc private func deleteTapped() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func globeTapped() {
        advanceToNextInputMode()
    }

    @objc private func microphoneTapped() {
        guard hasFullAccess else {
            statusLabel.text = "Enable Allow Full Access in iPhone Settings to use dictation."
            return
        }
        guard let exchangeStore else {
            statusLabel.text = "Shared Vox container unavailable."
            return
        }

        if let requestID = activeRequestID,
           let current = try? exchangeStore.load(),
           current.requestID == requestID {
            if current.phase == .recording {
                do {
                    _ = try exchangeStore.transition(requestID: requestID, to: .stopRequested)
                    refreshState()
                } catch {
                    statusLabel.text = "Could not stop dictation. Tap again to retry."
                }
            }
            return
        }

        do {
            let request = try exchangeStore.beginRequest()
            guard let requestID = request.requestID else { return }
            setActiveRequestID(requestID)
            refreshState()
            guard let url = URL(string: "vox://dictate?id=\(requestID.uuidString)") else { return }
            extensionContext?.open(url) { [weak self] opened in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !opened {
                        self.statusLabel.text = "Open Vox to start recording."
                    }
                    self.refreshState()
                }
            }
        } catch {
            statusLabel.text = "Could not start dictation: \(error.localizedDescription)"
        }
    }

    @objc private func cancelTapped() {
        guard let requestID = activeRequestID,
              let exchangeStore,
              let current = try? exchangeStore.load(),
              current.requestID == requestID,
              [.requestingHandoff, .recording, .stopRequested, .transcribing, .ready].contains(current.phase)
        else { return }
        _ = try? exchangeStore.transition(requestID: requestID, to: .cancelled)
        setActiveRequestID(nil)
        refreshState()
    }

    private func updateLetterCase() {
        for button in letterButtons {
            guard let title = button.configuration?.title else { continue }
            button.configuration?.title = isShifted ? title.uppercased() : title.lowercased()
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func refreshState() {
        guard let exchangeStore,
              let exchange = try? exchangeStore.load()
        else {
            statusLabel.text = "Vox keyboard ready"
            return
        }

        if activeRequestID == nil,
           let persisted = defaults?.string(forKey: activeRequestKey) {
            activeRequestID = UUID(uuidString: persisted)
        }

        let isCurrent = exchange.requestID == activeRequestID
        cancelButton.isHidden = !isCurrent || ![.requestingHandoff, .recording, .stopRequested, .transcribing].contains(exchange.phase)

        if isCurrent,
           exchange.phase == .ready,
           let requestID = activeRequestID,
           let createdAt = exchange.createdAt,
           view.window != nil {
            guard Date().timeIntervalSince(createdAt) <= 120 else {
                _ = try? exchangeStore.transition(requestID: requestID, to: .cancelled)
                setActiveRequestID(nil)
                statusLabel.text = "That transcription expired. Tap the mic to try again."
                setMicrophone(symbol: "arrow.clockwise", label: "Retry dictation", enabled: true)
                return
            }
            do {
                if let text = try exchangeStore.consumeReadyResult(requestID: requestID) {
                    textDocumentProxy.insertText(text)
                }
                setActiveRequestID(nil)
            } catch {
                statusLabel.text = "Your text is ready, but could not be inserted."
            }
            return
        }

        switch exchange.phase {
        case .requestingHandoff:
            statusLabel.text = "Opening Vox… swipe back after recording starts"
            setMicrophone(symbol: "hourglass", label: "Waiting for Vox", enabled: false)
        case .recording:
            statusLabel.text = "Recording — tap Stop when finished"
            setMicrophone(symbol: "stop.fill", label: "Stop dictation", enabled: true)
        case .stopRequested:
            statusLabel.text = "Stopping…"
            setMicrophone(symbol: "hourglass", label: "Stopping", enabled: false)
        case .transcribing:
            statusLabel.text = "Transcribing…"
            setMicrophone(symbol: "waveform", label: "Transcribing", enabled: false)
        case .ready:
            statusLabel.text = "Transcription ready"
            setMicrophone(symbol: "mic.fill", label: "Start dictation", enabled: true)
        case .failed:
            statusLabel.text = exchange.errorMessage ?? "Dictation failed. Tap the mic to retry."
            setMicrophone(symbol: "arrow.clockwise", label: "Retry dictation", enabled: true)
            if isCurrent { setActiveRequestID(nil) }
        case .cancelled:
            statusLabel.text = "Cancelled"
            setMicrophone(symbol: "mic.fill", label: "Start dictation", enabled: true)
            if isCurrent { setActiveRequestID(nil) }
        case .consumed:
            statusLabel.text = "Inserted"
            setMicrophone(symbol: "mic.fill", label: "Start dictation", enabled: true)
            if isCurrent { setActiveRequestID(nil) }
        case .idle:
            statusLabel.text = hasFullAccess ? "Vox keyboard ready" : "Typing works. Enable Full Access for dictation."
            setMicrophone(symbol: "mic.fill", label: "Start dictation", enabled: true)
        }
    }

    private func setMicrophone(symbol: String, label: String, enabled: Bool) {
        microphoneButton.configuration?.image = UIImage(systemName: symbol)
        microphoneButton.accessibilityLabel = label
        microphoneButton.isEnabled = enabled
    }

    private func setActiveRequestID(_ requestID: UUID?) {
        activeRequestID = requestID
        if let requestID {
            defaults?.set(requestID.uuidString, forKey: activeRequestKey)
        } else {
            defaults?.removeObject(forKey: activeRequestKey)
        }
    }
}
