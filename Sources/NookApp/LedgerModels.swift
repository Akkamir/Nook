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
}

struct LedgerState: Codable {
    let totalBits: Double
    let pendingBits: Double
    let agents: [String: AgentRecord]
    let lastUpdated: Date

    static var empty: LedgerState {
        LedgerState(totalBits: 0, pendingBits: 0, agents: [:], lastUpdated: Date())
    }
}
