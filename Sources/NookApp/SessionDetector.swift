import Foundation

@MainActor
final class SessionDetector {
    private let fm = FileManager.default
    private let claudeProjectsURL: URL
    private var hookActiveAgents: Set<String> = []
    private var recentlyEndedAgents: [String: Date] = [:]
    private var sessionAgents: [String: String] = [:]
    private var endedSessionIds: Set<String> = []
    private let recentlyEndedTTL: TimeInterval
    private let now: () -> Date

    init(
        claudeProjectsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        recentlyEndedTTL: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.claudeProjectsURL = claudeProjectsURL
        self.recentlyEndedTTL = recentlyEndedTTL
        self.now = now
    }

    @discardableResult
    func handleHookEvent(_ event: ClaudeHookEvent) -> Bool {
        pruneRecentlyEnded()
        if event.refreshesActivity,
           let sessionId = event.sessionId,
           endedSessionIds.contains(sessionId) {
            return false
        }

        guard let agent = agentName(for: event) else { return false }

        var changed = false

        if event.isSessionStart {
            if let sessionId = event.sessionId {
                if sessionAgents[sessionId] != agent {
                    sessionAgents[sessionId] = agent
                    changed = true
                }
                if endedSessionIds.remove(sessionId) != nil {
                    changed = true
                }
            }
            if recentlyEndedAgents.removeValue(forKey: agent) != nil {
                changed = true
            }
            changed = hookActiveAgents.insert(agent).inserted || changed
        } else if event.isSessionEnd {
            if let sessionId = event.sessionId {
                if sessionAgents.removeValue(forKey: sessionId) != nil {
                    changed = true
                }
                changed = endedSessionIds.insert(sessionId).inserted || changed
            }
            if hookActiveAgents.remove(agent) != nil {
                changed = true
            }
            recentlyEndedAgents[agent] = now()
            changed = true
        } else if event.refreshesActivity, recentlyEndedAgents[agent] == nil {
            if let sessionId = event.sessionId, sessionAgents[sessionId] != agent {
                sessionAgents[sessionId] = agent
                changed = true
            }
            changed = hookActiveAgents.insert(agent).inserted || changed
        }

        return changed
    }

    func detectActive() -> Set<String> {
        pruneRecentlyEnded()
        let cutoff = now().addingTimeInterval(-300)
        guard let entries = try? fm.contentsOfDirectory(
            at: claudeProjectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return hookActiveAgents }

        var active = hookActiveAgents
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if hasRecentJSONL(in: entry, since: cutoff),
               let name = agentName(forProjectDir: entry) {
                guard recentlyEndedAgents[name] == nil else { continue }
                active.insert(name)
            }
        }
        return active
    }

    private func hasRecentJSONL(in dir: URL, since cutoff: Date) -> Bool {
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return false }

        return contents.contains { url in
            guard url.pathExtension == "jsonl" else { return false }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (mod ?? .distantPast) > cutoff
        }
    }

    private func agentName(for event: ClaudeHookEvent) -> String? {
        if let sessionId = event.sessionId,
           let agent = sessionAgents[sessionId] {
            return agent
        }

        if let transcriptPath = event.transcriptPath {
            let projectDir = URL(fileURLWithPath: transcriptPath).deletingLastPathComponent()
            if let agent = agentName(forProjectDir: projectDir) {
                return agent
            }
        }

        if let cwd = event.cwd {
            return agentName(forProjectURL: URL(fileURLWithPath: cwd, isDirectory: true))
        }

        return nil
    }

    private func pruneRecentlyEnded() {
        let cutoff = now().addingTimeInterval(-recentlyEndedTTL)
        recentlyEndedAgents = recentlyEndedAgents.filter { $0.value > cutoff }
    }

    private func claudeProjectDirName(forPath path: String) -> String {
        String(path.map { character in
            guard let scalar = character.unicodeScalars.first else { return "-" }
            let value = scalar.value
            let isASCIIAlphaNumeric = (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value)
            return isASCIIAlphaNumeric || character == "-" ? character : "-"
        })
    }

    private func agentName(forProjectURL projectURL: URL) -> String? {
        let pixelvillageURL = projectURL.appendingPathComponent(".pixelvillage")
        guard let data = try? Data(contentsOf: pixelvillageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let agent = json["agent"] else { return nil }
        return agent
    }

    private func agentName(forProjectDir dir: URL) -> String? {
        let dirName = dir.lastPathComponent
        guard dirName.hasPrefix("-") else { return nil }
        let projectPath = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")
        return agentName(forProjectURL: URL(fileURLWithPath: projectPath, isDirectory: true))
    }
}
