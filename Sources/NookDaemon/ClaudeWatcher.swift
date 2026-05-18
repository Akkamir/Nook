import Foundation

final class ClaudeWatcher {
    private let projectsRoot: URL
    private let offsetsURL: URL
    private let onEvent: (TokenEvent, String?) -> Void
    private var fileOffsets: [String: UInt64] = [:]  // keyed by path string for JSON serialization
    private var dispatchSource: DispatchSourceProtocol?

    init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        offsetsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/offsets.json"),
        onEvent: @escaping (TokenEvent, String?) -> Void
    ) {
        self.projectsRoot = projectsRoot
        self.offsetsURL = offsetsURL
        self.onEvent = onEvent
        loadOffsets()
    }

    func start() {
        scanAllProjects()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2))
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

        let content = String(data: data, encoding: .utf8) ?? ""
        for line in content.components(separatedBy: "\n") {
            guard let parsed = TranscriptParser.parseLine(line) else { continue }
            let event = TokenEvent(
                projectPath: projectPath,
                inputTokens: parsed.inputTokens,
                outputTokens: parsed.outputTokens,
                timestamp: parsed.timestamp
            )
            onEvent(event, agentName)
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
