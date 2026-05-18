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
