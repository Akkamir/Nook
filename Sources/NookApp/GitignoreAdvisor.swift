import Foundation

struct GitignoreAdvisor {
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    func needsGlobalIgnoreOffer(forProjectPaths paths: [String]) -> Bool {
        guard paths.contains(where: { isInsideGitRepository(URL(fileURLWithPath: $0, isDirectory: true)) }) else {
            return false
        }
        return !globalIgnoreCoversPixelVillage()
    }

    func addPixelVillageToGlobalGitignore() throws {
        let url = globalIgnoreURL()
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !existing.components(separatedBy: .newlines).contains(".pixelvillage") else { return }
        let prefix = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try (existing + prefix + ".pixelvillage\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func globalIgnoreCoversPixelVillage() -> Bool {
        let url = globalIgnoreURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains(".pixelvillage")
    }

    private func globalIgnoreURL() -> URL {
        if let configured = gitConfigExcludesFile(), !configured.isEmpty {
            if configured.hasPrefix("~/") {
                return fm.homeDirectoryForCurrentUser.appendingPathComponent(String(configured.dropFirst(2)))
            }
            return URL(fileURLWithPath: configured)
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent(".gitignore_global")
    }

    private func gitConfigExcludesFile() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["config", "--global", "core.excludesFile"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func isInsideGitRepository(_ url: URL) -> Bool {
        var current = url
        while true {
            if fm.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return true
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return false }
            current = parent
        }
    }
}
