import Foundation

enum AgentAttributor {
    private struct Config: Decodable {
        let agent: String?
    }

    static func agentName(forProjectPath path: String, cwdHint: String? = nil) -> String? {
        // First try the real project directory by decoding the encoded dir name
        let dirName = URL(fileURLWithPath: path).lastPathComponent
        if dirName.hasPrefix("-") {
            let realPath = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")
            if let agent = readAgent(at: URL(fileURLWithPath: realPath)) {
                return agent
            }
        }
        // Second: look directly in the Claude project dir
        if let agent = readAgent(at: URL(fileURLWithPath: path)) {
            return agent
        }
        // Third: walk up from cwdHint (covers isolation: "worktree" scenarios where
        // the worktree is a subdirectory of a project that has .pixelvillage).
        guard let hint = cwdHint else { return nil }
        return agentByWalkingUp(from: hint)
    }

    // Walk up the directory tree from `cwdPath`, looking for .pixelvillage.
    // Stops after 6 levels or when reaching the user's home directory.
    private static func agentByWalkingUp(from cwdPath: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var current = URL(fileURLWithPath: cwdPath, isDirectory: true)
        for _ in 0..<6 {
            if let agent = readAgent(at: current) { return agent }
            if current.path == home { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }   // reached filesystem root
            current = parent
        }
        return nil
    }

    private static func readAgent(at url: URL) -> String? {
        let configURL = url.appendingPathComponent(".pixelvillage")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }
        return config.agent
    }
}
