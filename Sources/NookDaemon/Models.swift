import Foundation

/// Bit rates derived from Sonnet 4.6 relative pricing, anchored at 5 bits / 1k input tokens.
///   input $3.00 · cache write $3.75 · output $15.00 (per 1M tokens)
/// → weights, normalized on input: 1.0 / 1.25 / 5.0
/// cache read is excluded: in subagent sessions it re-reads the full context on every call,
/// causing quadratic accumulation that inflates NPC scores beyond what feels meaningful.
enum BitRate {
    static let bitsPerKInput = 5.0
    static let inputWeight = 1.0
    static let outputWeight = 5.0
    static let cacheWriteWeight = 1.25
    static let cacheReadWeight = 0.0

    static func bits(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) -> Double {
        weightedTokens(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead)
            / 1000.0 * bitsPerKInput
    }

    /// Same Sonnet 4.6 weights as bits, rounded — used for bond progression and session totals.
    static func bondTokens(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) -> Int {
        Int(weightedTokens(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead).rounded())
    }

    private static func weightedTokens(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) -> Double {
        Double(input) * inputWeight +
        Double(output) * outputWeight +
        Double(cacheCreation) * cacheWriteWeight +
        Double(cacheRead) * cacheReadWeight
    }
}

struct TokenEvent {
    let sessionId: String
    let projectPath: String
    let cwd: String?
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let timestamp: Date

    init(sessionId: String, projectPath: String, cwd: String?, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int = 0, cacheReadTokens: Int = 0, timestamp: Date) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.cwd = cwd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.timestamp = timestamp
    }

    var bits: Double {
        BitRate.bits(input: inputTokens, output: outputTokens,
                     cacheCreation: cacheCreationTokens, cacheRead: cacheReadTokens)
    }

    var bondTokens: Int {
        BitRate.bondTokens(input: inputTokens, output: outputTokens,
                           cacheCreation: cacheCreationTokens, cacheRead: cacheReadTokens)
    }
}

struct AgentRecord: Codable {
    var name: String
    var totalTokens: Int
    var bond: Int
    var totalBitsRaw: Double

    enum CodingKeys: String, CodingKey {
        case name
        case totalTokens
        case bond
        case totalBitsRaw = "totalBits"
    }

    init(name: String, totalTokens: Int = 0, bond: Int = 1, totalBitsRaw: Double = 0) {
        self.name = name
        self.totalTokens = totalTokens
        self.bond = bond
        self.totalBitsRaw = totalBitsRaw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        _ = try? c.decode(Int.self, forKey: .bond)
        bond = BondScale.level(for: totalTokens)
        // One-time migration: estimate bits from tokens only if the legacy field is absent.
        totalBitsRaw = try c.contains(.totalBitsRaw)
            ? c.decode(Double.self, forKey: .totalBitsRaw)
            : Double(totalTokens) * 10.0 / 1000.0
    }

    mutating func addTokens(_ event: TokenEvent, rawBits: Double) {
        totalTokens += event.bondTokens
        totalBitsRaw += rawBits
        bond = BondScale.level(for: totalTokens)
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
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var totalBits: Double

    // Subject signals (NPC voice)
    var task: String?
    var taskPromptCount: Int = 0
    var gitBranch: String?
    var filesTouched: [String] = []
    var editCount: Int = 0
    var readCount: Int = 0
    var bashCount: Int = 0
    var firedKinds: [String] = []

    var totalTokens: Int {
        BitRate.bondTokens(input: inputTokens, output: outputTokens,
                           cacheCreation: cacheCreationTokens, cacheRead: cacheReadTokens)
    }
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
        cacheCreationTokens = (try? c.decode(Int.self, forKey: .cacheCreationTokens)) ?? 0
        cacheReadTokens = (try? c.decode(Int.self, forKey: .cacheReadTokens)) ?? 0
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        task = try? c.decode(String.self, forKey: .task)
        taskPromptCount = (try? c.decode(Int.self, forKey: .taskPromptCount)) ?? 0
        gitBranch = try? c.decode(String.self, forKey: .gitBranch)
        filesTouched = (try? c.decode([String].self, forKey: .filesTouched)) ?? []
        editCount = (try? c.decode(Int.self, forKey: .editCount)) ?? 0
        readCount = (try? c.decode(Int.self, forKey: .readCount)) ?? 0
        bashCount = (try? c.decode(Int.self, forKey: .bashCount)) ?? 0
        firedKinds = (try? c.decode([String].self, forKey: .firedKinds)) ?? []
    }
}

struct LedgerState: Codable {
    var totalBitsRaw: Double
    var pendingBits: Double
    var globalBitsRaw: Double
    var agents: [String: AgentRecord]
    var lastUpdated: Date
    var recentEvents: [BitEvent]
    var eventSeq: Int
    var sessions: [String: SessionRecord]
    var recentActivity: [SessionActivityEvent]
    var activitySeq: Int

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
        LedgerState(totalBitsRaw: 0, pendingBits: 0, globalBitsRaw: 0, agents: [:], lastUpdated: Date(), recentEvents: [], eventSeq: 0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBitsRaw = try c.decode(Double.self, forKey: .totalBitsRaw)
        pendingBits = try c.decode(Double.self, forKey: .pendingBits)
        agents = try c.decode([String: AgentRecord].self, forKey: .agents)
        let agentBitsRaw = agents.values.reduce(0) { $0 + $1.totalBitsRaw }
        globalBitsRaw = (try? c.decode(Double.self, forKey: .globalBitsRaw)) ?? max(0, totalBitsRaw - agentBitsRaw)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        recentEvents = (try? c.decode([BitEvent].self, forKey: .recentEvents)) ?? []
        eventSeq = (try? c.decode(Int.self, forKey: .eventSeq)) ?? 0
        sessions = (try? c.decode([String: SessionRecord].self, forKey: .sessions)) ?? [:]
        recentActivity = (try? c.decode([SessionActivityEvent].self, forKey: .recentActivity)) ?? []
        activitySeq = (try? c.decode(Int.self, forKey: .activitySeq)) ?? 0
    }
}
