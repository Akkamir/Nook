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
        totalBits = (try? c.decode(Double.self, forKey: .totalBits)) ?? 0
    }
}

struct LedgerState: Codable {
    let totalBits: Double
    var pendingBits: Double
    let agents: [String: AgentRecord]
    let lastUpdated: Date

    static var empty: LedgerState {
        LedgerState(totalBits: 0, pendingBits: 0, agents: [:], lastUpdated: Date())
    }
}
