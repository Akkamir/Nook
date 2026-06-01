import Foundation

struct ProjectRollup: Equatable {
    let project: String
    let projectPath: String
    let totalTokens: Int
    let sessionCount: Int
    let firstSeen: Date
    let lastSeen: Date

    static func forAgent(_ sessions: [SessionRecord]) -> [ProjectRollup] {
        let groups = Dictionary(grouping: sessions, by: { $0.projectPath })
        return groups.compactMap { _, group -> ProjectRollup? in
            guard let first = group.first else { return nil }
            return ProjectRollup(
                project: first.project,
                projectPath: first.projectPath,
                totalTokens: group.reduce(0) { $0 + $1.totalTokens },
                sessionCount: group.count,
                firstSeen: group.map(\.startedAt).min() ?? first.startedAt,
                lastSeen: group.map(\.lastActivityAt).max() ?? first.lastActivityAt
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }
}
