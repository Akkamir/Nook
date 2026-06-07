import Foundation

struct NPCMemoryState: Codable, Equatable {
    var sessions: [String: GeneratedSessionMemory]

    init(sessions: [String: GeneratedSessionMemory] = [:]) {
        self.sessions = sessions
    }

    static var empty: NPCMemoryState { NPCMemoryState() }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = (try? c.decode([String: GeneratedSessionMemory].self, forKey: .sessions)) ?? [:]
    }
}

struct GeneratedSessionMemory: Codable, Equatable {
    let sessionId: String
    let agentName: String?
    var title: String
    var shortSummary: String
    var narrativeBeats: [String]
    var relationshipNote: String?
    var cachedLines: [String]
    var updatedAt: Date

    static func heuristic(for session: SessionRecord) -> GeneratedSessionMemory {
        let theme = themeText(for: session)
        let title = "\(theme) · \(session.project)"
        let summary = summaryText(for: session)
        let line = lineText(for: session, theme: theme)
        return GeneratedSessionMemory(
            sessionId: session.sessionId,
            agentName: session.agentName,
            title: title,
            shortSummary: summary,
            narrativeBeats: [summary],
            relationshipNote: relationshipText(forBond: session.totalTokens),
            cachedLines: [line],
            updatedAt: session.lastActivityAt
        )
    }

    private static func themeText(for session: SessionRecord) -> String {
        if let task = session.task, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return titleCasePrefix(task, wordLimit: 3)
        }
        if let firstFile = session.filesTouched.first {
            return "Work on \(URL(fileURLWithPath: firstFile).lastPathComponent)"
        }
        return "Session"
    }

    private static func summaryText(for session: SessionRecord) -> String {
        var parts: [String] = []
        if let task = session.task { parts.append("Task: \(truncate(task, to: 80))") }
        if !session.filesTouched.isEmpty {
            let files = session.filesTouched.prefix(3).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            parts.append("Files: \(files)")
        }
        if session.editCount > 0 { parts.append("\(session.editCount) edits") }
        if session.bashCount > 0 { parts.append("\(session.bashCount) commands") }
        return parts.isEmpty ? "A quiet session in \(session.project)." : parts.joined(separator: " · ")
    }

    private static func lineText(for session: SessionRecord, theme: String) -> String {
        let bond = BondScale.level(for: session.totalTokens)
        if bond >= 8 {
            return "I remember this rhythm: \(theme)."
        }
        if bond >= 4 {
            return "We're getting somewhere with \(theme)."
        }
        return "I started on \(theme)."
    }

    private static func relationshipText(forBond totalTokens: Int) -> String? {
        let bond = BondScale.level(for: totalTokens)
        if bond >= 8 { return "Familiar and emotionally warm." }
        if bond >= 4 { return "Trust is forming through repeated work." }
        return nil
    }

    private static func titleCasePrefix(_ text: String, wordLimit: Int) -> String {
        let words = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(wordLimit)
            .map(String.init)
        guard !words.isEmpty else { return "Session" }
        let normalized = words.enumerated().map { index, word in
            if word == word.uppercased(), word.count > 1 { return word }
            let lower = word.lowercased()
            return index == 0 ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
        }
        return normalized.joined(separator: " ")
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count <= limit ? clean : String(clean.prefix(limit - 3)) + "..."
    }
}

struct SessionDigest: Equatable {
    let project: String
    let branch: String?
    let recentUserAsks: [String]
    let files: [String]
    let commands: [String]
    let tools: [String]

    static func fromSession(_ session: SessionRecord) -> SessionDigest {
        SessionDigest(
            project: session.project,
            branch: session.gitBranch,
            recentUserAsks: session.task.map { [GeneratedSessionMemory.heuristicSnippet($0, limit: 160)] } ?? [],
            files: session.filesTouched.map { URL(fileURLWithPath: $0).lastPathComponent },
            commands: [],
            tools: []
        )
    }

    static func fromTranscript(_ content: String, project: String, maxTextLength: Int = 600) -> SessionDigest {
        var asks: [String] = []
        var files: [String] = []
        var commands: [String] = []
        var tools: [String] = []
        var branch: String?

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if branch == nil {
                branch = object["gitBranch"] as? String
            }
            if let message = object["message"] as? [String: Any] {
                if message["role"] as? String == "user",
                   let text = message["content"] as? String {
                    asks.append(bound(text, to: max(20, maxTextLength / 2)))
                }
                if let contentArray = message["content"] as? [[String: Any]] {
                    for item in contentArray {
                        guard item["type"] as? String == "tool_use",
                              let name = item["name"] as? String else { continue }
                        appendUnique(name, to: &tools, limit: 8)
                        let input = item["input"] as? [String: Any]
                        if let path = input?["file_path"] as? String {
                            appendUnique(URL(fileURLWithPath: path).lastPathComponent, to: &files, limit: 8)
                        }
                        if let command = input?["command"] as? String {
                            appendUnique(commandSummary(command), to: &commands, limit: 8)
                        }
                    }
                }
            }
        }

        let boundedAsks = boundAll(asks.suffix(3), totalLimit: maxTextLength)
        return SessionDigest(project: project, branch: branch, recentUserAsks: boundedAsks, files: files, commands: commands, tools: tools)
    }

    private static func appendUnique(_ value: String, to values: inout [String], limit: Int) {
        guard !value.isEmpty, !values.contains(value), values.count < limit else { return }
        values.append(value)
    }

    private static func commandSummary(_ command: String) -> String {
        let parts = command.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard let first = parts.first.map(String.init) else { return "" }
        if first == "git", parts.count > 1 { return "git \(parts[1])" }
        return first
    }

    private static func boundAll<S: Sequence>(_ texts: S, totalLimit: Int) -> [String] where S.Element == String {
        var remaining = totalLimit
        var result: [String] = []
        for text in texts {
            guard remaining > 0 else { break }
            let clipped = bound(text, to: remaining)
            result.append(clipped)
            remaining -= clipped.count
        }
        return result
    }

    private static func bound(_ text: String, to limit: Int) -> String {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count <= limit ? clean : String(clean.prefix(max(0, limit - 3))) + "..."
    }
}

extension GeneratedSessionMemory {
    fileprivate static func heuristicSnippet(_ text: String, limit: Int) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count <= limit ? clean : String(clean.prefix(limit - 3)) + "..."
    }
}

final class NPCMemoryStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelvillage/npc-memory.json")) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> NPCMemoryState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(NPCMemoryState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: NPCMemoryState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }
}
