import Foundation

final class ClaudeWatcher {
    private let projectsRoot: URL
    private let offsetsURL: URL
    private let onEvent: (TokenEvent, String?) -> Void
    private let onSubject: (ParsedEntry, String, String, String?) -> Void  // entry, sessionId, projectPath, agentName
    private var fileOffsets: [String: UInt64] = [:]  // keyed by path string for JSON serialization
    private var dispatchSource: DispatchSourceProtocol?

    init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        offsetsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/offsets.json"),
        onEvent: @escaping (TokenEvent, String?) -> Void,
        onSubject: @escaping (ParsedEntry, String, String, String?) -> Void = { _, _, _, _ in }
    ) {
        self.projectsRoot = projectsRoot
        self.offsetsURL = offsetsURL
        self.onEvent = onEvent
        self.onSubject = onSubject
        loadOffsets()
    }

    func start() {
        scanAllProjects()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.25, repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.scanAllProjects() }
        timer.resume()
        dispatchSource = timer

        print("[NookDaemon] Watching \(projectsRoot.path)")
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    private func scanAllProjects() {
        guard let projectDirs = try? FileManager.default
            .contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)
            .filter({ $0.hasDirectoryPath })
        else { return }

        for projectDir in projectDirs {
            scanProject(at: projectDir)
        }
    }

    private func scanProject(at projectDir: URL) {
        guard let jsonlFiles = try? FileManager.default
            .contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "jsonl" })
        else { return }

        let agentName = AgentAttributor.agentName(forProjectPath: projectDir.path)

        for jsonlFile in jsonlFiles {
            readNewLines(in: jsonlFile, projectPath: projectDir.path, agentName: agentName)
        }
    }

    private func readNewLines(in file: URL, projectPath: String, agentName: String?) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { handle.closeFile() }

        let key = file.path
        let offset = fileOffsets[key] ?? 0
        handle.seek(toFileOffset: offset)

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        fileOffsets[key] = offset + UInt64(data.count)
        saveOffsets()

        let sessionId = file.deletingPathExtension().lastPathComponent
        let content = String(data: data, encoding: .utf8) ?? ""
        var lastUsage: [Int]? = nil
        // resolvedAgent starts as the project-level attribution; refined lazily if a
        // cwd is found and the project-level lookup returned nil (worktree isolation).
        var resolvedAgent = agentName
        var cwdResolved = false
        for line in content.components(separatedBy: "\n") {
            guard let parsed = TranscriptParser.parseLine(line) else { continue }

            // If project-level attribution failed, try cwdHint once per file.
            if resolvedAgent == nil, !cwdResolved, let cwd = parsed.cwd {
                cwdResolved = true
                resolvedAgent = AgentAttributor.agentName(forProjectPath: projectPath, cwdHint: cwd)
            }

            // Subject ingestion runs for every message line (user prompts included).
            onSubject(parsed, sessionId, projectPath, resolvedAgent)

            // Token/bits emission only for usage-bearing lines (with consecutive-dup guard).
            let usage = [parsed.inputTokens, parsed.outputTokens,
                         parsed.cacheCreationTokens, parsed.cacheReadTokens]
            guard usage.contains(where: { $0 > 0 }) else { continue }
            guard lastUsage.map({ $0 != usage }) ?? true else { continue }
            lastUsage = usage
            let event = TokenEvent(
                sessionId: sessionId,
                projectPath: projectPath,
                cwd: parsed.cwd,
                inputTokens: parsed.inputTokens,
                outputTokens: parsed.outputTokens,
                cacheCreationTokens: parsed.cacheCreationTokens,
                cacheReadTokens: parsed.cacheReadTokens,
                timestamp: parsed.timestamp
            )
            onEvent(event, resolvedAgent)
        }
    }

    private func loadOffsets() {
        guard let data = try? Data(contentsOf: offsetsURL),
              let decoded = try? JSONDecoder().decode([String: UInt64].self, from: data)
        else { return }
        fileOffsets = decoded
    }

    private func saveOffsets() {
        guard let data = try? JSONEncoder().encode(fileOffsets) else { return }
        try? data.write(to: offsetsURL, options: .atomic)
    }
}
