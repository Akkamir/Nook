import Foundation

struct TokenEvent {
    let projectPath: String
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
}

struct SessionRecord: Codable, Equatable {
    let sessionId: String
    let project: String
    let projectPath: String
    let agentName: String?
    let startedAt: Date
    let lastActivityAt: Date
    let inputTokens: Int
    let outputTokens: Int
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    let totalBits: Double

    // Subject signals (NPC voice) — decode-only mirror; the daemon owns dedup (firedKinds).
    var task: String?
    var gitBranch: String?
    var filesTouched: [String] = []
    var editCount: Int = 0
    var readCount: Int = 0
    var bashCount: Int = 0

    var totalTokens: Int {
        // Mirror NookDaemon BitRate bond weights (Sonnet 4.6 relative pricing).
        let weighted = Double(inputTokens) * 1.0 +
            Double(outputTokens) * 5.0 +
            Double(cacheCreationTokens) * 1.25 +
            Double(cacheReadTokens) * 0.1
        return Int(weighted.rounded())
    }
    var duration: TimeInterval { lastActivityAt.timeIntervalSince(startedAt) }
}

extension SessionRecord {
    // Backward-compatible decode: existing ledgers have records without the
    // subject fields. In an extension to preserve the memberwise init.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        project = try c.decode(String.self, forKey: .project)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        agentName = try? c.decode(String.self, forKey: .agentName)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        cacheCreationTokens = (try? c.decode(Int.self, forKey: .cacheCreationTokens)) ?? 0
        cacheReadTokens = (try? c.decode(Int.self, forKey: .cacheReadTokens)) ?? 0
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        task = try? c.decode(String.self, forKey: .task)
        gitBranch = try? c.decode(String.self, forKey: .gitBranch)
        filesTouched = (try? c.decode([String].self, forKey: .filesTouched)) ?? []
        editCount = (try? c.decode(Int.self, forKey: .editCount)) ?? 0
        readCount = (try? c.decode(Int.self, forKey: .readCount)) ?? 0
        bashCount = (try? c.decode(Int.self, forKey: .bashCount)) ?? 0
    }
}

struct SessionActivityEvent: Codable, Equatable {
    let agentName: String?
    let sessionId: String
    let kind: String
    let payload: String?
    let seq: Int
}

struct AgentRecord: Codable {
    let name: String
    let totalTokens: Int
    let bond: Int
    let totalBitsRaw: Double

    enum CodingKeys: String, CodingKey {
        case name
        case totalTokens
        case bond
        case totalBitsRaw = "totalBits"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        _ = try? c.decode(Int.self, forKey: .bond)
        bond = BondScale.level(for: totalTokens)
        totalBitsRaw = try c.contains(.totalBitsRaw)
            ? c.decode(Double.self, forKey: .totalBitsRaw)
            : Double(totalTokens) * 10.0 / 1000.0
    }
}

struct BitEvent: Codable {
    let agentName: String?
    let rawBits: Double
    let seq: Int

    enum CodingKeys: String, CodingKey {
        case agentName
        case rawBits = "bits"
        case seq
    }
}

struct LedgerState: Codable {
    let totalBitsRaw: Double
    var pendingBits: Double
    let globalBitsRaw: Double
    let agents: [String: AgentRecord]
    let lastUpdated: Date
    let recentEvents: [BitEvent]
    let eventSeq: Int
    let sessions: [String: SessionRecord]
    let recentActivity: [SessionActivityEvent]
    let activitySeq: Int

    enum CodingKeys: String, CodingKey {
        case totalBitsRaw = "totalBits"
        case pendingBits
        case globalBitsRaw
        case agents
        case lastUpdated
        case recentEvents
        case eventSeq
        case sessions
        case recentActivity
        case activitySeq
    }

    init(totalBitsRaw: Double, pendingBits: Double, globalBitsRaw: Double = 0, agents: [String: AgentRecord], lastUpdated: Date, recentEvents: [BitEvent], eventSeq: Int, sessions: [String: SessionRecord] = [:], recentActivity: [SessionActivityEvent] = [], activitySeq: Int = 0) {
        self.totalBitsRaw = totalBitsRaw
        self.pendingBits = pendingBits
        self.globalBitsRaw = globalBitsRaw
        self.agents = agents
        self.lastUpdated = lastUpdated
        self.recentEvents = recentEvents
        self.eventSeq = eventSeq
        self.sessions = sessions
        self.recentActivity = recentActivity
        self.activitySeq = activitySeq
    }

    static var empty: LedgerState {
        LedgerState(totalBitsRaw: 0, pendingBits: 0, agents: [:], lastUpdated: Date(), recentEvents: [], eventSeq: 0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBitsRaw = try c.decode(Double.self, forKey: .totalBitsRaw)
        pendingBits = try c.decode(Double.self, forKey: .pendingBits)
        agents = try c.decode([String: AgentRecord].self, forKey: .agents)
        let agentBits = agents.values.reduce(0) { $0 + $1.totalBitsRaw }
        globalBitsRaw = (try? c.decode(Double.self, forKey: .globalBitsRaw)) ?? max(0, totalBitsRaw - agentBits)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        recentEvents = (try? c.decode([BitEvent].self, forKey: .recentEvents)) ?? []
        eventSeq = (try? c.decode(Int.self, forKey: .eventSeq)) ?? 0
        sessions = (try? c.decode([String: SessionRecord].self, forKey: .sessions)) ?? [:]
        recentActivity = (try? c.decode([SessionActivityEvent].self, forKey: .recentActivity)) ?? []
        activitySeq = (try? c.decode(Int.self, forKey: .activitySeq)) ?? 0
    }
}
