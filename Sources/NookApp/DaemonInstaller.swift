import Foundation

@MainActor
final class DaemonInstaller {
    static let shared = DaemonInstaller()
    private init() {}

    private let launchAgentLabel = "com.nook.daemon"
    private let fm = FileManager.default

    private(set) var isDaemonRunning: Bool = false

    private var plistURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.nook.daemon.plist")
    }

    private var daemonBinaryURL: URL? {
        guard let bundleURL = Bundle.main.executableURL else { return nil }
        return bundleURL.deletingLastPathComponent().appendingPathComponent("NookDaemon")
    }

    func installIfNeeded() {
        guard let binaryURL = daemonBinaryURL,
              fm.fileExists(atPath: binaryURL.path) else {
            print("[DaemonInstaller] NookDaemon binary not found in bundle")
            return
        }
        do {
            try writePlist(binaryURL: binaryURL)
            try bootstrapOrKickstart()
            isDaemonRunning = true
            print("[DaemonInstaller] NookDaemon installed and running")
        } catch {
            print("[DaemonInstaller] Failed: \(error)")
        }
    }

    private func writePlist(binaryURL: URL) throws {
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let homeDir = fm.homeDirectoryForCurrentUser.path
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryURL.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(homeDir)/.pixelvillage/daemon.log</string>
            <key>StandardErrorPath</key>
            <string>\(homeDir)/.pixelvillage/daemon-error.log</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    private func bootstrapOrKickstart() throws {
        let uid = getuid()
        let domain = "gui/\(uid)"

        let checkResult = runLaunchctl(["list", launchAgentLabel])
        if checkResult.status == 0 {
            _ = runLaunchctl(["kickstart", "-k", "\(domain)/\(launchAgentLabel)"])
        } else {
            let result = runLaunchctl(["bootstrap", domain, plistURL.path])
            if result.status != 0 {
                throw DaemonError.launchctlFailed(result.output)
            }
        }
    }

    private func runLaunchctl(_ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    enum DaemonError: Error {
        case launchctlFailed(String)
    }
}
