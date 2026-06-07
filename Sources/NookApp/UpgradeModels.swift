import Foundation

enum UpgradeKind: String, Codable, Equatable {
    case bitMultiplier
}

struct AgentUpgradeState: Codable, Equatable {
    var bitMultiplierLevel: Int
    var spentBits: Double
    var lastPurchasedAt: Date?

    init(bitMultiplierLevel: Int = 0, spentBits: Double = 0, lastPurchasedAt: Date? = nil) {
        self.bitMultiplierLevel = bitMultiplierLevel
        self.spentBits = spentBits
        self.lastPurchasedAt = lastPurchasedAt
    }

    var bitMultiplier: Double {
        1.0 + Double(bitMultiplierLevel) * 0.25
    }
}

struct UpgradeState: Codable, Equatable {
    var agents: [String: AgentUpgradeState]
    var lastUpdated: Date

    init(agents: [String: AgentUpgradeState] = [:], lastUpdated: Date = Date(timeIntervalSince1970: 0)) {
        self.agents = agents
        self.lastUpdated = lastUpdated
    }

    static var empty: UpgradeState {
        UpgradeState()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = (try? c.decode([String: AgentUpgradeState].self, forKey: .agents)) ?? [:]
        lastUpdated = (try? c.decode(Date.self, forKey: .lastUpdated)) ?? Date(timeIntervalSince1970: 0)
    }
}

enum UpgradeEconomy {
    static let bitMultiplierBaseCost: Double = 50
    static let bitMultiplierCostGrowth: Double = 1.8

    static func cost(for upgrade: UpgradeKind, currentLevel: Int) -> Double {
        switch upgrade {
        case .bitMultiplier:
            return bitMultiplierBaseCost * pow(bitMultiplierCostGrowth, Double(currentLevel))
        }
    }

    static func availableBits(for agentName: String, ledger: LedgerState, upgrades: UpgradeState) -> Double {
        guard let agent = ledger.agents[agentName] else { return 0 }
        let spent = upgrades.agents[agentName]?.spentBits ?? 0
        return max(0, agent.totalBits - spent)
    }

    @discardableResult
    static func apply(_ upgrade: UpgradeKind, for agentName: String, ledger: LedgerState, upgrades: inout UpgradeState) -> Bool {
        let currentLevel = upgrades.agents[agentName]?.bitMultiplierLevel ?? 0
        let upgradeCost = cost(for: upgrade, currentLevel: currentLevel)
        guard availableBits(for: agentName, ledger: ledger, upgrades: upgrades) >= upgradeCost else { return false }
        var agentState = upgrades.agents[agentName] ?? AgentUpgradeState()
        agentState.bitMultiplierLevel += 1
        agentState.spentBits += upgradeCost
        agentState.lastPurchasedAt = Date()
        upgrades.agents[agentName] = agentState
        return true
    }
}

final class EconomyStore {
    let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> UpgradeState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(UpgradeState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: UpgradeState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    static var production: EconomyStore {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelvillage")
        return EconomyStore(url: dir.appendingPathComponent("economy.json"))
    }
}
