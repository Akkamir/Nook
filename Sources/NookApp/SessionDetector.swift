import Foundation

@MainActor
final class SessionDetector {
    private let fm = FileManager.default
    private let claudeProjectsURL: URL

    init() {
        claudeProjectsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func detectActive() -> Set<String> {
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
               let name = agentName(forProjectDir: entry) {
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

    private func agentName(forProjectDir dir: URL) -> String? {
        let dirName = dir.lastPathComponent
        guard dirName.hasPrefix("-") else { return nil }
        let projectPath = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")
        let pixelvillageURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".pixelvillage")
        guard let data = try? Data(contentsOf: pixelvillageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let agent = json["agent"] else { return nil }
        return agent
    }
}
