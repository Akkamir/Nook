import Foundation

struct TokenEvent {
    let projectPath: String
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
        totalBits = (try? c.decode(Double.self, forKey: .totalBits)) ?? 0
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

struct LedgerState: Codable {
    var totalBits: Double
    var pendingBits: Double
    var agents: [String: AgentRecord]
    var lastUpdated: Date

    static var empty: LedgerState {
        LedgerState(
            totalBits: 0,
            pendingBits: 0,
            agents: [:],
            lastUpdated: Date()
        )
    }
}
