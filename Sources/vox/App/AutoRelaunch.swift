import Foundation

enum AutoRelaunch {
    static let launchAgentArgument = "--vox-launch-agent"
    private static let label = "com.andykumeda.vox"

    static var isLaunchAgentInstance: Bool {
        CommandLine.arguments.contains(launchAgentArgument)
    }

    static func installAndHandOffIfNeeded() {
        guard !isLaunchAgentInstance else { return }
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }

        do {
            let plistURL = try installLaunchAgent()
            let uid = getuid()
            _ = runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
            let bootstrapped = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
            guard bootstrapped else {
                dlog("auto relaunch: launchctl bootstrap failed; continuing unsupervised")
                return
            }
            let started = runLaunchctl(["kickstart", "-k", "gui/\(uid)/\(label)"])
            dlog("auto relaunch: installed launch agent at \(plistURL.path), kickstart=\(started)")
            exit(0)
        } catch {
            dlog("auto relaunch: install failed: \(error)")
        }
    }

    static func launchAgentPlist(
        executablePath: String,
        logDirectoryPath: String
    ) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executablePath, launchAgentArgument],
            "RunAtLoad": true,
            "KeepAlive": [
                "Crashed": true,
                "SuccessfulExit": false,
            ],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 5,
            "StandardOutPath": "\(logDirectoryPath)/vox.launchd.out.log",
            "StandardErrorPath": "\(logDirectoryPath)/vox.launchd.err.log",
        ]
    }

    private static func installLaunchAgent() throws -> URL {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let launchAgents = library.appendingPathComponent("LaunchAgents", isDirectory: true)
        let logs = library.appendingPathComponent("Logs", isDirectory: true)
        try fm.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)

        let plistURL = launchAgents.appendingPathComponent("\(label).plist")
        let plist = launchAgentPlist(
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0],
            logDirectoryPath: logs.path
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
        return plistURL
    }

    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            dlog("auto relaunch: launchctl \(arguments.joined(separator: " ")) failed: \(error)")
            return false
        }
    }
}
