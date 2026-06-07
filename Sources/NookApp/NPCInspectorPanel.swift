import SwiftUI

struct NPCInspectorPanel: View {
    let selection: NPCSelection
    let onClose: () -> Void

    private var progress: BondProgress {
        BondProgress.forTokens(selection.totalTokens)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                liveStrip
                statusSection
                statsSection
                progressSection
                if !selection.projects.isEmpty { projectsSection }
                if !selection.recentSessions.isEmpty { recentSessionsSection }
                if !selection.moments.isEmpty { momentsSection }
            }
            .padding(16)
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.76))
        .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.name)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(selection.trait.rawValue)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.78))
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("Close inspector")
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Status")
            HStack {
                Circle()
                    .fill(selection.activeSessionCount > 0 ? Color.green : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(selection.activeSessionCount > 0 ? "Working" : "Idle")
                Spacer()
                if selection.activeSessionCount > 0 {
                    Text("\(selection.activeSessionCount) session\(selection.activeSessionCount == 1 ? "" : "s")")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var liveStrip: some View {
        HStack(spacing: 8) {
            if selection.currentStreakDays > 0 {
                badge(icon: .streak, "\(selection.currentStreakDays)d")
            }
            if selection.longestSessionSeconds > 0 {
                badge(formatDuration(selection.longestSessionSeconds) + " max")
            }
            badge(icon: .bit, formatBits(selection.availableBits))
            if selection.bitMultiplier > 1.0 {
                badge(formatMultiplier(selection.bitMultiplier) + "x")
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(icon: PixelIconKind? = nil, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let icon {
                PixelIcon(kind: icon, size: 11)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var statsSection: some View {
        let spent = selection.totalBits - selection.availableBits
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Stats")
            VStack(alignment: .leading, spacing: 3) {
                statRow("Bits", formatBits(selection.availableBits))
                if spent > 0.01 {
                    HStack {
                        Spacer()
                        Text("\(formatBits(spent)) spent on upgrades")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
            }
            statRow("Tokens", formatInt(selection.totalTokens))
            statRow("Bond", "\(selection.bond)")
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Bond Progress")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.24))
                        .frame(width: max(0, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 8)
            Text(progress.label)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Projects")
            ForEach(selection.projects, id: \.projectPath) { p in
                HStack {
                    Text(p.project).lineLimit(1)
                    Spacer()
                    Text("\(formatInt(p.totalTokens)) · \(p.sessionCount) sess.")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recent Sessions")
            ForEach(selection.recentSessions, id: \.sessionId) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.sessionMemories[s.sessionId]?.title ?? s.project)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(shortDate(s.startedAt))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("\(formatDuration(s.duration)) · \(formatInt(s.totalTokens))")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                }
            }
        }
    }

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Moments")
            ForEach(Array(selection.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, m in
                HStack(alignment: .top, spacing: 8) {
                    PixelIcon(kind: icon(for: m.kind), size: 14)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.label).foregroundStyle(.white.opacity(0.88))
                        Text(Moment.displayDate(m.date))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func icon(for kind: Moment.Kind) -> PixelIconKind {
        switch kind {
        case .firstSession, .firstOnProject: return .spark
        case .anniversary: return .cake
        case .bondPromotion: return .bond
        case .streakRecord: return .streak
        case .tokenMilestone, .sessionMilestone, .hoursMilestone: return .milestone
        case .longestSession, .biggestSession, .mostProductiveDay: return .trophy
        case .nightSession: return .night
        case .returnAfterAbsence: return .returnArrow
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)m"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.48))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
        }
    }

    private func formatInt(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func formatMultiplier(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private func formatBits(_ bits: Double) -> String {
        if bits >= 1_000_000 { return String(format: "%.1fM", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.1fk", bits / 1_000) }
        if bits >= 10 { return String(format: "%.0f", bits) }
        return String(format: "%.1f", bits)
    }
}
