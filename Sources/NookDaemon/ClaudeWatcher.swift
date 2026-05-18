import Foundation

final class ClaudeWatcher {
    private let projectsRoot: URL
    private let onEvent: (TokenEvent, String?) -> Void
    private var fileOffsets: [URL: UInt64] = [:]
    private var dispatchSource: DispatchSourceProtocol?

    init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        onEvent: @escaping (TokenEvent, String?) -> Void
    ) {
        self.projectsRoot = projectsRoot
        self.onEvent = onEvent
    }

    func start() {
        let fd = open(projectsRoot.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[NookDaemon] Cannot watch \(projectsRoot.path)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.scanAllProjects()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.dispatchSource = src

        scanAllProjects()
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

        let offset = fileOffsets[file] ?? 0
        handle.seek(toFileOffset: offset)

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        fileOffsets[file] = offset + UInt64(data.count)

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
}
