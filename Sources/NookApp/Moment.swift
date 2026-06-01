import Foundation

struct MomentSummary: Equatable {
    let currentStreakDays: Int
    let longestSessionSeconds: TimeInterval
}

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

    static let tokenMilestones = [100_000, 250_000, 500_000, 1_000_000]
    static let sessionMilestones = [10, 50, 100]
    static let hoursMilestones = [10, 50, 100]

    static func forAgent(_ sessions: [SessionRecord], now: Date = Date(),
                         calendar: Calendar = .current) -> [Moment] {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        guard !ordered.isEmpty else { return [] }

        var moments: [Moment] = []
        moments += anchorMoments(ordered, now: now, calendar: calendar)
        moments += livingMoments(ordered, calendar: calendar)
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

    private static func livingMoments(_ ordered: [SessionRecord], calendar: Calendar) -> [Moment] {
        var out: [Moment] = []
        let bondTokenSet = Set(bondThresholds.map(\.tokens))

        // Cumulative token milestones (skip any that coincide with a bond threshold).
        var cumulative = 0
        var tokenAwarded = Set<Int>()
        var sessionIndex = 0
        for s in ordered {
            cumulative += s.totalTokens
            sessionIndex += 1
            for m in tokenMilestones where cumulative >= m && !tokenAwarded.contains(m) && !bondTokenSet.contains(m) {
                tokenAwarded.insert(m)
                out.append(Moment(kind: .tokenMilestone(m), date: s.lastActivityAt,
                                  label: "\(formatTokens(m)) tokens together"))
            }
            if sessionMilestones.contains(sessionIndex) {
                out.append(Moment(kind: .sessionMilestone(sessionIndex), date: s.startedAt,
                                  label: "\(sessionIndex)th session together"))
            }
        }

        // Cumulative hours milestones.
        var cumulativeSeconds: TimeInterval = 0
        var hoursAwarded = Set<Int>()
        for s in ordered {
            cumulativeSeconds += max(0, s.duration)
            let hours = Int(cumulativeSeconds / 3600)
            for h in hoursMilestones where hours >= h && !hoursAwarded.contains(h) {
                hoursAwarded.insert(h)
                out.append(Moment(kind: .hoursMilestone(h), date: s.lastActivityAt,
                                  label: "\(h)h together"))
            }
        }

        // Beatable records (emit one moment for the record holder).
        if let longest = ordered.max(by: { $0.duration < $1.duration }), longest.duration > 0 {
            out.append(Moment(kind: .longestSession(seconds: longest.duration), date: longest.lastActivityAt,
                              label: "Longest session · \(formatDuration(longest.duration))"))
        }
        if let biggest = ordered.max(by: { $0.totalTokens < $1.totalTokens }), biggest.totalTokens > 0 {
            out.append(Moment(kind: .biggestSession(tokens: biggest.totalTokens), date: biggest.lastActivityAt,
                              label: "Biggest session · \(formatTokens(biggest.totalTokens))"))
        }
        let byDay = Dictionary(grouping: ordered) { calendar.startOfDay(for: $0.startedAt) }
        if let best = byDay.map({ (day: $0.key, tokens: $0.value.reduce(0) { $0 + $1.totalTokens }) })
            .max(by: { $0.tokens < $1.tokens }), best.tokens > 0 {
            out.append(Moment(kind: .mostProductiveDay(tokens: best.tokens), date: best.day,
                              label: "Most productive day · \(formatTokens(best.tokens))"))
        }

        // Streak record (longest run of consecutive local days with a session).
        let record = longestStreak(ordered, calendar: calendar)
        if record.days >= 2, let endDate = record.endDate {
            out.append(Moment(kind: .streakRecord(days: record.days), date: endDate,
                              label: "\(record.days)-day streak"))
        }

        // Night sessions (active between 00:00 and 05:00 local).
        for s in ordered {
            if overlapsNightWindow(s, calendar: calendar) {
                out.append(Moment(kind: .nightSession, date: s.startedAt, label: "Late-night session"))
            }
        }

        // Return after absence (>= 14 days gap between consecutive sessions).
        for (prev, next) in zip(ordered, ordered.dropFirst()) {
            let gapDays = calendar.dateComponents([.day], from: prev.startedAt, to: next.startedAt).day ?? 0
            if gapDays >= 14 {
                out.append(Moment(kind: .returnAfterAbsence(days: gapDays), date: next.startedAt,
                                  label: "Back after \(gapDays) days"))
            }
        }

        return out
    }

    static func summary(_ sessions: [SessionRecord], now: Date = Date(),
                        calendar: Calendar = .current) -> MomentSummary {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        let longest = ordered.map(\.duration).max() ?? 0
        return MomentSummary(
            currentStreakDays: currentStreak(ordered, now: now, calendar: calendar),
            longestSessionSeconds: max(0, longest)
        )
    }

    // MARK: - Streak math

    private static func dayStarts(_ sessions: [SessionRecord], calendar: Calendar) -> [Date] {
        Array(Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })).sorted()
    }

    private static func longestStreak(_ sessions: [SessionRecord], calendar: Calendar) -> (days: Int, endDate: Date?) {
        let days = dayStarts(sessions, calendar: calendar)
        guard let first = days.first else { return (0, nil) }
        var best = 1
        var bestEnd = first
        var run = 1
        for (prev, next) in zip(days, days.dropFirst()) {
            if calendar.dateComponents([.day], from: prev, to: next).day == 1 { run += 1 }
            else { run = 1 }
            if run > best {
                best = run
                bestEnd = next
            }
        }
        return (best, bestEnd)
    }

    private static func overlapsNightWindow(_ session: SessionRecord, calendar: Calendar) -> Bool {
        let start = session.startedAt
        let end = max(session.lastActivityAt, start)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        var day = startDay
        while day <= endDay {
            guard let nightEnd = calendar.date(byAdding: .hour, value: 5, to: day) else { return false }
            if start < nightEnd && end > day {
                return true
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return false
    }

    private static func currentStreak(_ sessions: [SessionRecord], now: Date, calendar: Calendar) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }
        // A streak is "current" if it includes today or yesterday.
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    // MARK: - Formatting

    private static func formatTokens(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return "\(v / 1_000)k" }
        return "\(v)"
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)m"
    }
}
