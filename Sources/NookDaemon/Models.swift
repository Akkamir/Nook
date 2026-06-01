import Foundation

struct TokenEvent {
    let sessionId: String
    let projectPath: String
    let cwd: String?
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date

    var bits: Double {
        Double(inputTokens) / 1000.0 * 5.0 +
        Double(outputTokens) / 1000.0 * 15.0
    }
}

struct AgentRecord: Codable {
    var name: String
    var totalTokens: Int
    var bond: Int
    var totalBits: Double

    init(name: String, totalTokens: Int = 0, bond: Int = 1, totalBits: Double = 0) {
        self.name = name
        self.totalTokens = totalTokens
        self.bond = bond
        self.totalBits = totalBits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        bond = try c.decode(Int.self, forKey: .bond)
        let decodedBits = (try? c.decode(Double.self, forKey: .totalBits)) ?? 0
        let decodedTokens = try c.decode(Int.self, forKey: .totalTokens)
        // One-time migration: estimate bits from tokens if field was absent
        totalBits = decodedBits > 0 ? decodedBits : Double(decodedTokens) * 10.0 / 1000.0
    }

    mutating func addTokens(_ event: TokenEvent) {
        totalTokens += event.inputTokens + event.outputTokens
        totalBits += event.bits
        bond = bondLevel(for: totalTokens)
    }

    private func bondLevel(for tokens: Int) -> Int {
        switch tokens {
        case ..<10_000: return 1
        case ..<50_000: return 2
        case ..<200_000: return 3
        case ..<1_000_000: return 4
        default: return 5
        }
    }
}

struct BitEvent: Codable {
    let agentName: String?
    let bits: Double
    let seq: Int
}

struct SessionActivityEvent: Codable, Equatable {
    let agentName: String?
    let sessionId: String
    let kind: String
    let payload: String?
    let seq: Int
}

struct SessionRecord: Codable, Equatable {
    let sessionId: String
    var project: String
    let projectPath: String
    var agentName: String?
    let startedAt: Date
    var lastActivityAt: Date
    var inputTokens: Int
    var outputTokens: Int
    var totalBits: Double

    // Subject signals (NPC voice)
    var task: String?
    var gitBranch: String?
    var filesTouched: [String] = []
    var editCount: Int = 0
    var readCount: Int = 0
    var bashCount: Int = 0
    var firedKinds: [String] = []

    var totalTokens: Int { inputTokens + outputTokens }
    var duration: TimeInterval { lastActivityAt.timeIntervalSince(startedAt) }
}

extension SessionRecord {
    // Backward-compatible decode: existing ledgers have records without the
    // subject fields. Defined in an extension to preserve the memberwise init.
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
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        task = try? c.decode(String.self, forKey: .task)
        gitBranch = try? c.decode(String.self, forKey: .gitBranch)
        filesTouched = (try? c.decode([String].self, forKey: .filesTouched)) ?? []
        editCount = (try? c.decode(Int.self, forKey: .editCount)) ?? 0
        readCount = (try? c.decode(Int.self, forKey: .readCount)) ?? 0
        bashCount = (try? c.decode(Int.self, forKey: .bashCount)) ?? 0
        firedKinds = (try? c.decode([String].self, forKey: .firedKinds)) ?? []
    }
}

struct LedgerState: Codable {
    var totalBits: Double
    var pendingBits: Double
    var agents: [String: AgentRecord]
    var lastUpdated: Date
    var recentEvents: [BitEvent]
    var eventSeq: Int
    var sessions: [String: SessionRecord]
    var recentActivity: [SessionActivityEvent]
    var activitySeq: Int

    init(totalBits: Double, pendingBits: Double, agents: [String: AgentRecord], lastUpdated: Date, recentEvents: [BitEvent], eventSeq: Int, sessions: [String: SessionRecord] = [:], recentActivity: [SessionActivityEvent] = [], activitySeq: Int = 0) {
        self.totalBits = totalBits
        self.pendingBits = pendingBits
        self.agents = agents
        self.lastUpdated = lastUpdated
        self.recentEvents = recentEvents
        self.eventSeq = eventSeq
        self.sessions = sessions
        self.recentActivity = recentActivity
        self.activitySeq = activitySeq
    }

    static var empty: LedgerState {
        LedgerState(totalBits: 0, pendingBits: 0, agents: [:], lastUpdated: Date(), recentEvents: [], eventSeq: 0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        pendingBits = try c.decode(Double.self, forKey: .pendingBits)
        agents = try c.decode([String: AgentRecord].self, forKey: .agents)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        recentEvents = (try? c.decode([BitEvent].self, forKey: .recentEvents)) ?? []
        eventSeq = (try? c.decode(Int.self, forKey: .eventSeq)) ?? 0
        sessions = (try? c.decode([String: SessionRecord].self, forKey: .sessions)) ?? [:]
        recentActivity = (try? c.decode([SessionActivityEvent].self, forKey: .recentActivity)) ?? []
        activitySeq = (try? c.decode(Int.self, forKey: .activitySeq)) ?? 0
    }
}
