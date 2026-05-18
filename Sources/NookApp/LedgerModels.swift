import Foundation

struct TokenEvent {
    let projectPath: String
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
}

struct AgentRecord: Codable {
    var name: String
    var totalTokens: Int
    var bond: Int
}

struct LedgerState: Codable {
    var totalBits: Double
    var pendingBits: Double
    var agents: [String: AgentRecord]
    var lastUpdated: Date

    static var empty: LedgerState {
        LedgerState(totalBits: 0, pendingBits: 0, agents: [:], lastUpdated: Date())
    }
}
