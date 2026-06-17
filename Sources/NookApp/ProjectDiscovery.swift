import Foundation

struct DiscoveredProject: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let displayName: String
    let lastActivityAt: Date
}

struct ProjectDiscovery {
    let projectsURL: URL
    private let fm: FileManager

    init(
        projectsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        fileManager: FileManager = .default
    ) {
        self.projectsURL = projectsURL
        self.fm = fileManager
    }

    func discover() -> [DiscoveredProject] {
        guard let dirs = try? fm.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return dirs.compactMap { dir -> DiscoveredProject? in
            guard ((try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true),
                  let path = Self.decodeProjectPath(fromClaudeDirectoryName: dir.lastPathComponent),
                  fm.fileExists(atPath: path)
            else { return nil }

            let activity = lastActivityDate(in: dir)
            return DiscoveredProject(
                path: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                lastActivityAt: activity
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastActivityAt == rhs.lastActivityAt { return lhs.path < rhs.path }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    static func decodeProjectPath(fromClaudeDirectoryName name: String) -> String? {
        guard name.hasPrefix("-"), name.count > 1 else { return nil }
        return "/" + String(name.dropFirst()).replacingOccurrences(of: "-", with: "/")
    }

    static func encodeProjectPathForTests(_ path: String) -> String {
        "-" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")
    }

    private func lastActivityDate(in dir: URL) -> Date {
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return ((try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
                ?? Date(timeIntervalSince1970: 0)
        }

        let jsonlDates = files.compactMap { file -> Date? in
            guard file.pathExtension == "jsonl",
                  ((try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true)
            else { return nil }
            return (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return jsonlDates.max()
            ?? ((try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
            ?? Date(timeIntervalSince1970: 0)
    }
}
