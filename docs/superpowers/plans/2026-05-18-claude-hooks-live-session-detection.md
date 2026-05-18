# Claude Hooks Live Session Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Claude Code hooks to Nook so NPC active state follows real `SessionStart` / `SessionEnd` lifecycle events, with the Phase 7 JSONL mtime scan retained as fallback.

**Architecture:** Nook starts a localhost-only HTTP server, writes `~/.pixelvillage/hook-server.json`, installs an idempotent Claude hook script into `~/.pixelvillage/hooks/claude-hook.py`, and merges Nook-owned hook entries into `~/.claude/settings.json`. Hook events flow into `SessionDetector`, which maintains live hook state and combines it with the existing JSONL fallback.

**Tech Stack:** Swift 6, macOS 14, SpriteKit app target, Foundation, POSIX sockets for a minimal local HTTP server, Python 3 for the Claude hook bridge script.

---

## File Structure

- Create `Sources/NookApp/ClaudeHookEvent.swift`
  - Codable model for hook events and hook server config.
  - Small pure helpers for event names and extracting `transcript_path` / `cwd`.

- Create `Sources/NookApp/ClaudeHookInstaller.swift`
  - Writes the Python hook script.
  - Merges hook entries into Claude settings idempotently.
  - Injectable paths for temp-directory tests.

- Create `Sources/NookApp/ClaudeHookServer.swift`
  - Local HTTP server bound to `127.0.0.1`.
  - Writes `hook-server.json`.
  - Validates bearer token and forwards decoded events.

- Modify `Sources/NookApp/SessionDetector.swift`
  - Add hook state: active agents, recently ended agents, session-to-agent hints.
  - Add `handleHookEvent(_:)`.
  - Keep JSONL fallback but suppress it for recently ended agents.

- Modify `Sources/NookApp/VillageEngine.swift`
  - Start/stop hook server.
  - Install hooks.
  - Update `activeSessions` immediately when hook events arrive.

- Verify `NookApp.xcodeproj/project.pbxproj`
  - Add new Swift files if the Xcode project does not auto-include them.

---

### Task 1: Hook Event Model

**Files:**
- Create: `Sources/NookApp/ClaudeHookEvent.swift`
- Probe: `/private/tmp/nook_hook_event_probe.swift`

- [ ] **Step 1: Write the failing probe**

Create `/private/tmp/nook_hook_event_probe.swift`:

```swift
import Foundation

@main
struct HookEventProbe {
    static func main() throws {
        let json = """
        {
          "hook_event_name": "SessionStart",
          "session_id": "abc123",
          "transcript_path": "/Users/mchau/.claude/projects/-Users-mchau-Radion/abc123.jsonl",
          "cwd": "/Users/mchau/Radion"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: json)
        precondition(event.name == "SessionStart")
        precondition(event.sessionId == "abc123")
        precondition(event.transcriptPath?.hasSuffix("abc123.jsonl") == true)
        precondition(event.cwd == "/Users/mchau/Radion")

        let config = ClaudeHookServerConfig(port: 54321, token: "secret")
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ClaudeHookServerConfig.self, from: encoded)
        precondition(decoded.port == 54321)
        precondition(decoded.token == "secret")
    }
}
```

- [ ] **Step 2: Run the probe and verify it fails**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /private/tmp/nook_hook_event_probe.swift -o /private/tmp/nook_hook_event_probe
```

Expected: FAIL because `ClaudeHookEvent.swift` does not exist.

- [ ] **Step 3: Implement `ClaudeHookEvent.swift`**

Add:

```swift
import Foundation

struct ClaudeHookEvent: Decodable {
    let name: String
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let source: String?
    let reason: String?
    let notificationType: String?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case name = "hook_event_name"
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case source
        case reason
        case notificationType = "notification_type"
        case toolName = "tool_name"
    }

    var isSessionStart: Bool { name == "SessionStart" }
    var isSessionEnd: Bool { name == "SessionEnd" }
    var refreshesActivity: Bool {
        ["PreToolUse", "PostToolUse", "Stop", "Notification"].contains(name)
    }
}

struct ClaudeHookServerConfig: Codable {
    let port: Int
    let token: String
}
```

- [ ] **Step 4: Run the probe and verify it passes**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /private/tmp/nook_hook_event_probe.swift -o /private/tmp/nook_hook_event_probe && /private/tmp/nook_hook_event_probe
```

Expected: exit `0`.

- [ ] **Step 5: Commit**

Run:

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/ClaudeHookEvent.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase8): add Claude hook event models"
```

---

### Task 2: Claude Hook Installer

**Files:**
- Create: `Sources/NookApp/ClaudeHookInstaller.swift`
- Probe: `/private/tmp/nook_hook_installer_probe.swift`

- [ ] **Step 1: Write the failing probe**

Create `/private/tmp/nook_hook_installer_probe.swift`:

```swift
import Foundation

@main
struct HookInstallerProbe {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nook-hook-installer-\(UUID().uuidString)")
        let claudeDir = root.appendingPathComponent(".claude")
        let pixelDir = root.appendingPathComponent(".pixelvillage")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        let original = """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "python3 -c 'print(1)'",
                    "timeout": 5
                  }
                ]
              }
            ],
            "PreCompact": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "python3 -c 'print(2)'",
                    "timeout": 5
                  }
                ]
              }
            ]
          },
          "language": "french"
        }
        """
        try original.write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = ClaudeHookInstaller(claudeDirectory: claudeDir, pixelVillageDirectory: pixelDir)
        try installer.install()
        try installer.install()

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(json["language"] as? String == "french")

        let hooks = json["hooks"] as! [String: Any]
        precondition(hooks["PreCompact"] != nil)
        for event in ClaudeHookInstaller.hookEvents {
            let entries = hooks[event] as! [[String: Any]]
            let nookEntries = entries.filter { entry in
                let hookList = entry["hooks"] as? [[String: Any]] ?? []
                return hookList.contains { hook in
                    (hook["command"] as? String)?.contains(".pixelvillage/hooks/claude-hook.py") == true
                }
            }
            precondition(nookEntries.count == 1, "expected exactly one Nook hook for \\(event)")
        }

        let hookScript = pixelDir.appendingPathComponent("hooks/claude-hook.py")
        precondition(FileManager.default.isExecutableFile(atPath: hookScript.path))
    }
}
```

- [ ] **Step 2: Run the probe and verify it fails**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookInstaller.swift /private/tmp/nook_hook_installer_probe.swift -o /private/tmp/nook_hook_installer_probe
```

Expected: FAIL because `ClaudeHookInstaller.swift` does not exist.

- [ ] **Step 3: Implement `ClaudeHookInstaller.swift`**

Add a focused installer with these public pieces:

```swift
import Foundation

struct ClaudeHookInstaller {
    static let hookEvents = [
        "SessionStart",
        "SessionEnd",
        "Stop",
        "Notification",
        "PreToolUse",
        "PostToolUse"
    ]

    private let fm = FileManager.default
    private let claudeDirectory: URL
    private let pixelVillageDirectory: URL

    init(
        claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude"),
        pixelVillageDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage")
    ) {
        self.claudeDirectory = claudeDirectory
        self.pixelVillageDirectory = pixelVillageDirectory
    }

    func install() throws {
        try writeHookScript()
        try mergeClaudeSettings()
    }

    private var settingsURL: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    private var hookScriptURL: URL {
        pixelVillageDirectory.appendingPathComponent("hooks/claude-hook.py")
    }

    private var hookCommand: String {
        "python3 \"\(hookScriptURL.path)\""
    }
}
```

Implement helpers:

```swift
private extension ClaudeHookInstaller {
    func writeHookScript() throws {
        let dir = hookScriptURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try hookScript.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hookScriptURL.path)
    }

    func mergeClaudeSettings() throws {
        try fm.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in Self.hookEvents {
            let existing = hooks[event] as? [[String: Any]] ?? []
            let filtered = existing.filter { !isNookHookEntry($0) }
            hooks[event] = filtered + [makeHookEntry()]
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    func readSettings() throws -> [String: Any] {
        guard fm.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { return [:] }
        return dictionary
    }

    func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        let tmp = settingsURL.appendingPathExtension("nook-tmp")
        try data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: settingsURL.path) {
            try fm.removeItem(at: settingsURL)
        }
        try fm.moveItem(at: tmp, to: settingsURL)
    }

    func makeHookEntry() -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                [
                    "type": "command",
                    "command": hookCommand,
                    "timeout": 5
                ]
            ]
        ]
    }

    func isNookHookEntry(_ entry: [String: Any]) -> Bool {
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { hook in
            (hook["command"] as? String)?.contains(".pixelvillage/hooks/claude-hook.py") == true
        }
    }
}
```

Add the script body:

```swift
private extension ClaudeHookInstaller {
    var hookScript: String {
        """
        #!/usr/bin/env python3
        import json
        import os
        import urllib.request

        def main():
            try:
                raw = os.read(0, 65536).decode("utf-8")
                event = json.loads(raw) if raw.strip() else {}
                config_path = os.path.expanduser("~/.pixelvillage/hook-server.json")
                with open(config_path, "r", encoding="utf-8") as f:
                    config = json.load(f)
                body = json.dumps(event).encode("utf-8")
                req = urllib.request.Request(
                    f"http://127.0.0.1:{config['port']}/claude-hook",
                    data=body,
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {config['token']}",
                    },
                    method="POST",
                )
                urllib.request.urlopen(req, timeout=1.0).read()
            except Exception:
                pass

        if __name__ == "__main__":
            main()
        """
    }
}
```

- [ ] **Step 4: Run the probe and verify it passes**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookInstaller.swift /private/tmp/nook_hook_installer_probe.swift -o /private/tmp/nook_hook_installer_probe && /private/tmp/nook_hook_installer_probe
```

Expected: exit `0`.

- [ ] **Step 5: Commit**

Run:

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/ClaudeHookInstaller.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase8): install Claude hook bridge"
```

---

### Task 3: Local Hook Server

**Files:**
- Create: `Sources/NookApp/ClaudeHookServer.swift`
- Probe: `/private/tmp/nook_hook_server_probe.swift`

- [ ] **Step 1: Write the failing probe**

Create `/private/tmp/nook_hook_server_probe.swift`:

```swift
import Foundation

@main
struct HookServerProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nook-hook-server-\(UUID().uuidString)")
        let server = ClaudeHookServer(pixelVillageDirectory: root)

        let received = DispatchSemaphore(value: 0)
        var receivedName: String?
        await MainActor.run {
            server.onEvent = { event in
                receivedName = event.name
                received.signal()
            }
        }

        try await MainActor.run { try server.start() }
        let configURL = root.appendingPathComponent("hook-server.json")
        let config = try JSONDecoder().decode(ClaudeHookServerConfig.self, from: Data(contentsOf: configURL))

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(config.port)/claude-hook")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = #"{"hook_event_name":"SessionStart","session_id":"abc"}"#.data(using: .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        precondition((response as! HTTPURLResponse).statusCode == 204)
        precondition(received.wait(timeout: .now() + 2) == .success)
        precondition(receivedName == "SessionStart")

        var bad = URLRequest(url: URL(string: "http://127.0.0.1:\(config.port)/claude-hook")!)
        bad.httpMethod = "POST"
        bad.httpBody = #"{"hook_event_name":"SessionStart"}"#.data(using: .utf8)
        let (_, badResponse) = try await URLSession.shared.data(for: bad)
        precondition((badResponse as! HTTPURLResponse).statusCode == 401)

        await MainActor.run { server.stop() }
    }
}
```

- [ ] **Step 2: Run the probe and verify it fails**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookServer.swift /private/tmp/nook_hook_server_probe.swift -o /private/tmp/nook_hook_server_probe
```

Expected: FAIL because `ClaudeHookServer.swift` does not exist.

- [ ] **Step 3: Implement `ClaudeHookServer.swift`**

Implement `@MainActor final class ClaudeHookServer` with:

```swift
import Foundation
import Darwin

@MainActor
final class ClaudeHookServer {
    var onEvent: ((ClaudeHookEvent) -> Void)?

    private let pixelVillageDirectory: URL
    private let queue = DispatchQueue(label: "nook.claude-hook-server")
    private var socketFD: Int32 = -1
    private var token = UUID().uuidString
    private(set) var port: Int = 0
    private var isRunning = false

    init(pixelVillageDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".pixelvillage")) {
        self.pixelVillageDirectory = pixelVillageDirectory
    }

    func start() throws {
        guard !isRunning else { return }
        socketFD = try makeListeningSocket()
        isRunning = true
        try writeConfig()
        acceptLoop()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}
```

Use POSIX sockets:

```swift
private extension ClaudeHookServer {
    func makeListeningSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = Darwin.getsockname(fd, $0, &length)
            }
        }
        port = Int(UInt16(bigEndian: bound.sin_port))
        return fd
    }

    func writeConfig() throws {
        try FileManager.default.createDirectory(at: pixelVillageDirectory, withIntermediateDirectories: true)
        let config = ClaudeHookServerConfig(port: port, token: token)
        let data = try JSONEncoder().encode(config)
        try data.write(to: pixelVillageDirectory.appendingPathComponent("hook-server.json"), options: .atomic)
    }
}
```

Implement request handling:

```swift
private extension ClaudeHookServer {
    func acceptLoop() {
        let fd = socketFD
        queue.async { [weak self] in
            while true {
                let client = Darwin.accept(fd, nil, nil)
                if client < 0 { break }
                self?.handle(client: client)
                Darwin.close(client)
            }
        }
    }

    func handle(client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(client, &buffer, buffer.count)
        guard count > 0 else { return }
        let request = String(decoding: buffer.prefix(count), as: UTF8.self)
        guard request.hasPrefix("POST /claude-hook ") else {
            writeResponse(client, status: 404)
            return
        }
        guard request.range(of: "Authorization: Bearer \(token)", options: [.caseInsensitive]) != nil else {
            writeResponse(client, status: 401)
            return
        }
        guard let separator = request.range(of: "\r\n\r\n") else {
            writeResponse(client, status: 400)
            return
        }
        let body = String(request[separator.upperBound...])
        guard let data = body.data(using: .utf8),
              let event = try? JSONDecoder().decode(ClaudeHookEvent.self, from: data) else {
            writeResponse(client, status: 400)
            return
        }
        Task { @MainActor [weak self] in
            self?.onEvent?(event)
        }
        writeResponse(client, status: 204)
    }

    func writeResponse(_ client: Int32, status: Int) {
        let reason = [204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found"][status] ?? "OK"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { Darwin.write(client, $0, strlen($0)) }
    }
}
```

- [ ] **Step 4: Run the probe and verify it passes**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookServer.swift /private/tmp/nook_hook_server_probe.swift -o /private/tmp/nook_hook_server_probe && /private/tmp/nook_hook_server_probe
```

Expected: exit `0`.

- [ ] **Step 5: Commit**

Run:

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/ClaudeHookServer.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase8): add local Claude hook server"
```

---

### Task 4: SessionDetector Hook State

**Files:**
- Modify: `Sources/NookApp/SessionDetector.swift`
- Probe: `/private/tmp/nook_session_detector_hook_probe.swift`

- [ ] **Step 1: Write the failing probe**

Create `/private/tmp/nook_session_detector_hook_probe.swift`:

```swift
import Foundation

@main
struct SessionDetectorHookProbe {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nook-session-detector-\(UUID().uuidString)")
        let project = root.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try #"{"agent":"Radion"}"#.write(
            to: project.appendingPathComponent(".pixelvillage"),
            atomically: true,
            encoding: .utf8
        )

        let claudeProjects = root.appendingPathComponent(".claude/projects")
        let encoded = "-private-tmp-\(root.lastPathComponent)-Project"
        let claudeProject = claudeProjects.appendingPathComponent(encoded)
        try FileManager.default.createDirectory(at: claudeProject, withIntermediateDirectories: true)
        let jsonl = claudeProject.appendingPathComponent("abc.jsonl")
        try "{}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let detector = SessionDetector(claudeProjectsURL: claudeProjects)
        let start = ClaudeHookEvent(
            name: "SessionStart",
            sessionId: "abc",
            transcriptPath: jsonl.path,
            cwd: nil,
            source: nil,
            reason: nil,
            notificationType: nil,
            toolName: nil
        )
        precondition(detector.handleHookEvent(start) == true)
        precondition(detector.detectActive().contains("Radion"))

        let end = ClaudeHookEvent(
            name: "SessionEnd",
            sessionId: "abc",
            transcriptPath: jsonl.path,
            cwd: nil,
            source: nil,
            reason: "exit",
            notificationType: nil,
            toolName: nil
        )
        precondition(detector.handleHookEvent(end) == true)
        precondition(!detector.detectActive().contains("Radion"))
    }
}
```

- [ ] **Step 2: Run the probe and verify it fails**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/SessionDetector.swift /private/tmp/nook_session_detector_hook_probe.swift -o /private/tmp/nook_session_detector_hook_probe
```

Expected: FAIL because `SessionDetector` has no injectable initializer and no `handleHookEvent`.

- [ ] **Step 3: Implement hook state in `SessionDetector.swift`**

Change the initializer:

```swift
init(claudeProjectsURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/projects")) {
    self.claudeProjectsURL = claudeProjectsURL
}
```

Add properties:

```swift
private var hookActiveAgents: Set<String> = []
private var recentlyEndedAgents: [String: Date] = [:]
private var sessionAgents: [String: String] = [:]
private let recentlyEndedTTL: TimeInterval = 300
```

Add event handling:

```swift
@discardableResult
func handleHookEvent(_ event: ClaudeHookEvent) -> Bool {
    pruneRecentlyEnded()
    guard let agent = agentName(forHookEvent: event) else { return false }
    if let sessionId = event.sessionId {
        sessionAgents[sessionId] = agent
    }

    if event.isSessionStart {
        recentlyEndedAgents.removeValue(forKey: agent)
        return hookActiveAgents.insert(agent).inserted
    }

    if event.isSessionEnd {
        let wasActive = hookActiveAgents.remove(agent) != nil
        recentlyEndedAgents[agent] = Date()
        return wasActive
    }

    if event.refreshesActivity, recentlyEndedAgents[agent] == nil {
        return hookActiveAgents.insert(agent).inserted
    }

    return false
}
```

Update `detectActive()` to combine hook state and fallback:

```swift
func detectActive() -> Set<String> {
    pruneRecentlyEnded()
    return hookActiveAgents.union(detectJSONLFallbackActive())
}
```

Move the existing scan body into `detectJSONLFallbackActive()` and skip recently ended agents:

```swift
private func detectJSONLFallbackActive() -> Set<String> {
    let cutoff = Date().addingTimeInterval(-300)
    guard let entries = try? fm.contentsOfDirectory(
        at: claudeProjectsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    ) else { return [] }

    var active: Set<String> = []
    for entry in entries {
        guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
        if hasRecentJSONL(in: entry, since: cutoff),
           let name = agentName(forProjectDir: entry),
           recentlyEndedAgents[name] == nil {
            active.insert(name)
        }
    }
    return active
}
```

Add hook mapping helpers:

```swift
private func agentName(forHookEvent event: ClaudeHookEvent) -> String? {
    if let sessionId = event.sessionId, let agent = sessionAgents[sessionId] {
        return agent
    }
    if let transcriptPath = event.transcriptPath {
        let dir = URL(fileURLWithPath: transcriptPath).deletingLastPathComponent()
        return agentName(forProjectDir: dir)
    }
    if let cwd = event.cwd {
        let dirName = cwd.replacingOccurrences(of: "[^a-zA-Z0-9-]", with: "-", options: .regularExpression)
        return agentName(forProjectDir: claudeProjectsURL.appendingPathComponent(dirName))
    }
    return nil
}

private func pruneRecentlyEnded() {
    let cutoff = Date().addingTimeInterval(-recentlyEndedTTL)
    recentlyEndedAgents = recentlyEndedAgents.filter { $0.value > cutoff }
}
```

- [ ] **Step 4: Run the probe and verify it passes**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/SessionDetector.swift /private/tmp/nook_session_detector_hook_probe.swift -o /private/tmp/nook_session_detector_hook_probe && /private/tmp/nook_session_detector_hook_probe
```

Expected: exit `0`.

- [ ] **Step 5: Commit**

Run:

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/SessionDetector.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase8): track active sessions from Claude hooks"
```

---

### Task 5: Wire Hooks Into VillageEngine

**Files:**
- Modify: `Sources/NookApp/VillageEngine.swift`

- [ ] **Step 1: Add hook server properties**

In `VillageEngine`, add:

```swift
private let hookServer = ClaudeHookServer()
private let hookInstaller = ClaudeHookInstaller()
```

- [ ] **Step 2: Start hooks before the session timer**

In `start()`, after `startDayNightTimer()` and before `startSessionTimer()`:

```swift
startHookServer()
```

Add:

```swift
private func startHookServer() {
    hookServer.onEvent = { [weak self] event in
        guard let self else { return }
        if self.sessionDetector.handleHookEvent(event) {
            self.activeSessions = self.sessionDetector.detectActive()
        }
    }

    do {
        try hookServer.start()
        try hookInstaller.install()
    } catch {
        print("Nook Claude hooks disabled: \(error)")
    }
}
```

- [ ] **Step 3: Stop the server**

In `stop()`, before `isRunning = false`:

```swift
hookServer.stop()
```

- [ ] **Step 4: Build and fix Xcode project membership if needed**

Run:

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: if files are not in the Xcode project, errors mention missing symbols such as `ClaudeHookServer` or `ClaudeHookInstaller`.

If needed, add these files to the Xcode project source phase:

- `Sources/NookApp/ClaudeHookEvent.swift`
- `Sources/NookApp/ClaudeHookInstaller.swift`
- `Sources/NookApp/ClaudeHookServer.swift`

Use the existing `PBXFileReference`, `PBXBuildFile`, and `PBXSourcesBuildPhase` pattern in `NookApp.xcodeproj/project.pbxproj`.

- [ ] **Step 5: Build again**

Run:

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

Run:

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/VillageEngine.swift NookApp.xcodeproj/project.pbxproj
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase8): wire Claude hooks into village engine"
```

---

### Task 6: End-to-End Hook Verification

**Files:**
- No production code expected unless verification exposes a bug.

- [ ] **Step 1: Run full app build**

Run:

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Run all probes**

Run:

```bash
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /private/tmp/nook_hook_event_probe.swift -o /private/tmp/nook_hook_event_probe && /private/tmp/nook_hook_event_probe
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookInstaller.swift /private/tmp/nook_hook_installer_probe.swift -o /private/tmp/nook_hook_installer_probe && /private/tmp/nook_hook_installer_probe
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookServer.swift /private/tmp/nook_hook_server_probe.swift -o /private/tmp/nook_hook_server_probe && /private/tmp/nook_hook_server_probe
swiftc /Users/mchau/Desktop/Code/Nook/Sources/NookApp/ClaudeHookEvent.swift /Users/mchau/Desktop/Code/Nook/Sources/NookApp/SessionDetector.swift /private/tmp/nook_session_detector_hook_probe.swift -o /private/tmp/nook_session_detector_hook_probe && /private/tmp/nook_session_detector_hook_probe
```

Expected: all commands exit `0`.

- [ ] **Step 3: Verify installed settings preserve existing hooks**

Run after launching Nook once:

```bash
python3 -m json.tool /Users/mchau/.claude/settings.json >/tmp/nook-settings-check.json
rg 'coach-os|radion-memory-os|claude-hook.py|PreCompact|SessionStart|SessionEnd' /tmp/nook-settings-check.json
```

Expected:

- existing Coach/Radion hook content remains present;
- `PreCompact` remains present;
- Nook `claude-hook.py` entries are present for configured lifecycle events.

- [ ] **Step 4: Manual live test**

Run Nook, then open a Claude Code session in a project containing:

```json
{ "agent": "Radion" }
```

Expected:

- NPC becomes active shortly after session start;
- `~/.pixelvillage/hook-server.json` exists;
- `~/.pixelvillage/hooks/claude-hook.py` exists and is executable.

Exit the Claude session.

Expected:

- NPC becomes inactive shortly after `SessionEnd`;
- the NPC does not remain active solely because the JSONL file was modified recently.

- [ ] **Step 5: Final commit if verification required fixes**

If Task 6 required code changes:

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp NookApp.xcodeproj/project.pbxproj
git -C /Users/mchau/Desktop/Code/Nook commit -m "fix(phase8): stabilize Claude hook session detection"
```

If no fixes were required, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Hooks live lifecycle detection: Tasks 2, 3, 4, 5.
- Local server and token auth: Task 3.
- Hook script and settings merge preserving existing hooks: Task 2 and Task 6.
- JSONL fallback and recently ended suppression: Task 4.
- Immediate engine update: Task 5.
- Build/manual verification: Task 6.

Placeholder scan:

- No `TBD`, `TODO`, or "implement later" placeholders.
- Each task has concrete files, commands, expected results, and code snippets.

Type consistency:

- `ClaudeHookEvent`, `ClaudeHookServerConfig`, `ClaudeHookInstaller`, and `ClaudeHookServer` names are introduced before use.
- `SessionDetector.handleHookEvent(_:)` returns `Bool` consistently for immediate engine refresh.
