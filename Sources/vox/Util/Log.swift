import Foundation

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

private let logQueue = DispatchQueue(label: "vox.log")

@inline(__always) public func dlog(_ msg: @autoclosure () -> String) {
    let line = "\(isoFormatter.string(from: Date())) [vox] \(msg())\n"
    let data = Data(line.utf8)
    logQueue.async {
        FileHandle.standardError.write(data)
        try? logHandle?.write(contentsOf: data)
    }
}
