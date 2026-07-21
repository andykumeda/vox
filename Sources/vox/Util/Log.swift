import Foundation

private let logURL: URL = {
    let fm = FileManager.default
    let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
    try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
    return logs.appendingPathComponent("vox.log")
}()

private let maximumLogBytes: UInt64 = 5 * 1024 * 1024

private let logHandle: FileHandle? = {
    try? prepareLogFile(at: logURL, maximumBytes: maximumLogBytes)
    guard let h = try? FileHandle(forWritingTo: logURL) else { return nil }
    _ = try? h.seekToEnd()
    return h
}()

private let isoFormatStyle = Date.ISO8601FormatStyle(
    dateSeparator: .dash,
    dateTimeSeparator: .standard,
    timeSeparator: .colon,
    timeZoneSeparator: .colon,
    includingFractionalSeconds: true,
    timeZone: TimeZone(secondsFromGMT: 0)!
)

private let logQueue = DispatchQueue(label: "vox.log")
private let mirrorDLogToStandardError = shouldMirrorDLogToStandardError(
    isLaunchAgentInstance: AutoRelaunch.isLaunchAgentInstance
)

func shouldMirrorDLogToStandardError(isLaunchAgentInstance: Bool) -> Bool {
    !isLaunchAgentInstance
}

func formatDLogLine(
    message: String,
    date: Date
) -> String {
    "\(date.formatted(isoFormatStyle)) [vox] \(message)\n"
}

/// Prepares a log file for append-only use. Oversized files rotate once at
/// startup to `<name>.previous`; the older previous generation is discarded.
func prepareLogFile(
    at logURL: URL,
    maximumBytes: UInt64,
    fileManager: FileManager = .default
) throws {
    try fileManager.createDirectory(
        at: logURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    if maximumBytes > 0, fileManager.fileExists(atPath: logURL.path) {
        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if size >= maximumBytes {
            let previousURL = logURL.appendingPathExtension("previous")
            if fileManager.fileExists(atPath: previousURL.path) {
                try fileManager.removeItem(at: previousURL)
            }
            try fileManager.moveItem(at: logURL, to: previousURL)
        }
    }

    if !fileManager.fileExists(atPath: logURL.path) {
        guard fileManager.createFile(atPath: logURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// Writes once to Vox's primary log. Interactive runs also mirror to stderr;
/// launch-agent runs use stderr only as a fallback when the primary write fails.
func writeDLogData(
    _ data: Data,
    to logHandle: FileHandle?,
    standardError: FileHandle = .standardError,
    mirrorToStandardError: Bool
) {
    var wroteToPrimaryLog = false
    if let logHandle {
        do {
            try logHandle.write(contentsOf: data)
            wroteToPrimaryLog = true
        } catch {
            // stderr remains available as a fallback below.
        }
    }

    if mirrorToStandardError || !wroteToPrimaryLog {
        try? standardError.write(contentsOf: data)
    }
}

/// Produces useful text diagnostics without putting user-authored content in logs.
/// Counts characters and whitespace-delimited words in one pass without allocating
/// an array of substrings.
func textLogMetrics(label: String, text: String) -> String {
    var characterCount = 0
    var wordCount = 0
    var isInsideWord = false

    for character in text {
        characterCount += 1
        if character.isWhitespace {
            isInsideWord = false
        } else if !isInsideWord {
            wordCount += 1
            isInsideWord = true
        }
    }

    return "\(label)_chars=\(characterCount) \(label)_words=\(wordCount)"
}

@inline(__always) public func dlog(_ msg: @autoclosure () -> String) {
    let message = msg()
    let date = Date()
    logQueue.async {
        let line = formatDLogLine(
            message: message,
            date: date
        )
        writeDLogData(
            Data(line.utf8),
            to: logHandle,
            mirrorToStandardError: mirrorDLogToStandardError
        )
    }
}
