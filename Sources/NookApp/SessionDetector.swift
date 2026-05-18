import Foundation

actor SessionDetector {
    private let fm = FileManager.default
    private let claudeProjectsURL: URL
    private var hookActiveAgents: Set<String> = []
    private var recentlyEndedAgents: [String: Date] = [:]
    private var sessionAgents: [String: (agent: String, seenAt: Date)] = [:]
    private var endedSessionIds: [String: Date] = [:]
    private var claudeProjectDirAgentCache: [String: String] = [:]
    private var claudeProjectDirMissCache: [String: Date] = [:]
    private let recentlyEndedTTL: TimeInterval
    private let projectDirMissTTL: TimeInterval
    private let now: () -> Date

    init(
        claudeProjectsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        recentlyEndedTTL: TimeInterval = 300,
        projectDirMissTTL: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.claudeProjectsURL = claudeProjectsURL
        self.recentlyEndedTTL = recentlyEndedTTL
        self.projectDirMissTTL = projectDirMissTTL
        self.now = now
    }

    @discardableResult
    func handleHookEvent(_ event: ClaudeHookEvent) -> Bool {
        pruneState()
        if event.refreshesActivity,
           let sessionId = event.sessionId,
           endedSessionIds[sessionId] != nil {
            return false
        }
        if event.refreshesActivity,
           ["Stop", "Notification"].contains(event.name),
           let sessionId = event.sessionId,
           sessionAgents[sessionId] == nil {
            return false
        }

        guard let agent = agentName(for: event) else { return false }

        var changed = false
        let timestamp = now()

        if event.isSessionStart {
            if let sessionId = event.sessionId {
                if sessionAgents[sessionId]?.agent != agent {
                    changed = true
                }
                sessionAgents[sessionId] = (agent: agent, seenAt: timestamp)
                if endedSessionIds.removeValue(forKey: sessionId) != nil {
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
                if endedSessionIds[sessionId] == nil {
                    changed = true
                }
                endedSessionIds[sessionId] = timestamp
            }
            if hookActiveAgents.remove(agent) != nil {
                changed = true
            }
            recentlyEndedAgents[agent] = timestamp
            changed = true
        } else if event.refreshesActivity, recentlyEndedAgents[agent] == nil {
            if let sessionId = event.sessionId {
                if sessionAgents[sessionId]?.agent != agent {
                    changed = true
                }
                sessionAgents[sessionId] = (agent: agent, seenAt: timestamp)
            }
            changed = hookActiveAgents.insert(agent).inserted || changed
        }

        return changed
    }

    func detectActive() -> Set<String> {
        pruneState()
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
           let session = sessionAgents[sessionId] {
            return session.agent
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

    private func pruneState() {
        let timestamp = now()
        let cutoff = timestamp.addingTimeInterval(-recentlyEndedTTL)
        recentlyEndedAgents = recentlyEndedAgents.filter { $0.value > cutoff }
        sessionAgents = sessionAgents.filter { $0.value.seenAt > cutoff }
        endedSessionIds = endedSessionIds.filter { $0.value > cutoff }
        claudeProjectDirMissCache = claudeProjectDirMissCache.filter {
            timestamp.timeIntervalSince($0.value) < projectDirMissTTL
        }
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
        if let agent = claudeProjectDirAgentCache[dirName] {
            return agent
        }

        let encodedLookup = agentNameForEncodedClaudeProjectDirName(dirName)
        if let agent = encodedLookup.agent {
            claudeProjectDirAgentCache[dirName] = agent
            claudeProjectDirMissCache.removeValue(forKey: dirName)
            return agent
        }

        // Legacy compatibility: early versions guessed the path by turning every
        // hyphen back into "/", which is lossy for real paths containing hyphens.
        let projectPath = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")
        if let agent = agentName(forProjectURL: URL(fileURLWithPath: projectPath, isDirectory: true)) {
            claudeProjectDirAgentCache[dirName] = agent
            claudeProjectDirMissCache.removeValue(forKey: dirName)
            return agent
        }

        if encodedLookup.searched {
            claudeProjectDirMissCache[dirName] = now()
        }
        return nil
    }

    private func agentNameForEncodedClaudeProjectDirName(_ dirName: String) -> (agent: String?, searched: Bool) {
        if let missedAt = claudeProjectDirMissCache[dirName],
           now().timeIntervalSince(missedAt) < projectDirMissTTL {
            return (nil, false)
        }

        for root in candidateProjectSearchRoots(for: dirName) {
            if let agent = agentNameForEncodedClaudeProjectDirName(dirName, under: root) {
                claudeProjectDirAgentCache[dirName] = agent
                claudeProjectDirMissCache.removeValue(forKey: dirName)
                return (agent, true)
            }
        }
        return (nil, true)
    }

    private func candidateProjectSearchRoots(for dirName: String) -> [URL] {
        var roots = [claudeProjectsURL.deletingLastPathComponent().deletingLastPathComponent()]

        if dirName.hasPrefix("-private-tmp-") {
            roots.append(URL(fileURLWithPath: "/private/tmp", isDirectory: true))
        }
        if dirName.hasPrefix("-tmp-") {
            roots.append(URL(fileURLWithPath: "/tmp", isDirectory: true))
        }

        let homePrefix = claudeProjectDirName(forPath: fm.homeDirectoryForCurrentUser.path) + "-"
        if dirName.hasPrefix(homePrefix) {
            roots.append(fm.homeDirectoryForCurrentUser)
        }

        var seen: Set<String> = []
        return roots.compactMap { root in
            let searchPath = root.path
            let canonicalPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: searchPath, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !seen.contains(where: { pathContains($0, canonicalPath) || pathContains(canonicalPath, $0) }),
                  seen.insert(canonicalPath).inserted else { return nil }
            return URL(fileURLWithPath: searchPath, isDirectory: true)
        }
    }

    private func pathContains(_ parent: String, _ child: String) -> Bool {
        let normalizedParent = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        return normalizedParent == child || child.hasPrefix(normalizedParent + "/")
    }

    private func agentNameForEncodedClaudeProjectDirName(_ dirName: String, under root: URL) -> String? {
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsPackageDescendants]
        ) else { return nil }

        let rootPath = root.path
        let maxDepth = 8
        var bestMatch: (depth: Int, agent: String)?

        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDirectory,
               url.lastPathComponent.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }

            let depth = pathDepth(of: url.path, relativeTo: rootPath)
            if depth >= maxDepth, isDirectory {
                enumerator.skipDescendants()
            }

            guard url.lastPathComponent == ".pixelvillage" else { continue }

            let projectURL = url.deletingLastPathComponent()
            guard claudeProjectDirName(forPath: projectURL.path) == dirName else { continue }
            guard let agent = agentName(forProjectURL: projectURL) else { continue }
            let projectDepth = pathDepth(of: projectURL.path, relativeTo: rootPath)
            if bestMatch == nil || projectDepth < bestMatch!.depth {
                bestMatch = (depth: projectDepth, agent: agent)
            }
        }

        return bestMatch?.agent
    }

    private func pathDepth(of path: String, relativeTo rootPath: String) -> Int {
        guard path.hasPrefix(rootPath) else { return Int.max }
        let relative = path.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return 0 }
        return relative.split(separator: "/").count
    }
}
