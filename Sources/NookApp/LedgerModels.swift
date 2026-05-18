import Foundation

struct TokenEvent {
    let projectPath: String
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
}

struct AgentRecord: Codable {
    let name: String
    let totalTokens: Int
    let bond: Int
    let totalBits: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        bond = try c.decode(Int.self, forKey: .bond)
        let decodedBits = (try? c.decode(Double.self, forKey: .totalBits)) ?? 0
        let decodedTokens = try c.decode(Int.self, forKey: .totalTokens)
        totalBits = decodedBits > 0 ? decodedBits : Double(decodedTokens) * 10.0 / 1000.0
    }
}

struct BitEvent: Codable {
    let agentName: String?
    let bits: Double
    let seq: Int
}

struct LedgerState: Codable {
    let totalBits: Double
    var pendingBits: Double
    let agents: [String: AgentRecord]
    let lastUpdated: Date
    let recentEvents: [BitEvent]
    let eventSeq: Int

    init(totalBits: Double, pendingBits: Double, agents: [String: AgentRecord], lastUpdated: Date, recentEvents: [BitEvent], eventSeq: Int) {
        self.totalBits = totalBits
        self.pendingBits = pendingBits
        self.agents = agents
        self.lastUpdated = lastUpdated
        self.recentEvents = recentEvents
        self.eventSeq = eventSeq
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
    }
}
