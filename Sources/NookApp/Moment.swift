import Foundation

struct Moment: Equatable {
    enum Kind: Equatable {
        case firstSession
        case firstOnProject(String)
        case anniversary(years: Int)
        case bondPromotion(level: Int)
        case streakRecord(days: Int)
        case tokenMilestone(Int)
        case sessionMilestone(Int)
        case hoursMilestone(Int)
        case longestSession(seconds: TimeInterval)
        case biggestSession(tokens: Int)
        case mostProductiveDay(tokens: Int)
        case nightSession
        case returnAfterAbsence(days: Int)
    }

    let kind: Kind
    let date: Date
    let label: String

    static let bondThresholds: [(level: Int, tokens: Int)] =
        [(2, 10_000), (3, 50_000), (4, 200_000), (5, 1_000_000)]

    static func forAgent(_ sessions: [SessionRecord], now: Date = Date(),
                         calendar: Calendar = .current) -> [Moment] {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        guard !ordered.isEmpty else { return [] }

        var moments: [Moment] = []
        moments += anchorMoments(ordered, now: now, calendar: calendar)
        // Task 7 appends living moments here.
        return moments.sorted { $0.date < $1.date }
    }

    private static func anchorMoments(_ ordered: [SessionRecord], now: Date,
                                      calendar: Calendar) -> [Moment] {
        var out: [Moment] = []

        if let first = ordered.first {
            out.append(Moment(kind: .firstSession, date: first.startedAt,
                              label: "First session together"))
        }

        var seenProjects = Set<String>()
        for session in ordered where !seenProjects.contains(session.projectPath) {
            seenProjects.insert(session.projectPath)
            out.append(Moment(kind: .firstOnProject(session.project), date: session.startedAt,
                              label: "First day on \(session.project)"))
        }

        var cumulative = 0
        var awarded = Set<Int>()
        for session in ordered {
            cumulative += session.totalTokens
            for threshold in bondThresholds
                where cumulative >= threshold.tokens && !awarded.contains(threshold.level) {
                awarded.insert(threshold.level)
                out.append(Moment(kind: .bondPromotion(level: threshold.level),
                                  date: session.lastActivityAt,
                                  label: "Bond \(threshold.level) reached"))
            }
        }

        if let first = ordered.first {
            let completedYears = calendar.dateComponents([.year], from: first.startedAt, to: now).year ?? 0
            let candidateYears = Set([max(1, completedYears), completedYears + 1])

            for years in candidateYears.sorted() where years >= 1 {
                if let anniversary = calendar.date(byAdding: .year, value: years, to: first.startedAt) {
                    let daysAway = abs(calendar.dateComponents([.day], from: now, to: anniversary).day ?? 99)
                    if daysAway <= 3 {
                        out.append(Moment(kind: .anniversary(years: years), date: anniversary,
                                          label: "\(years) year\(years == 1 ? "" : "s") together"))
                        break
                    }
                }
            }
        }

        return out
    }
}
