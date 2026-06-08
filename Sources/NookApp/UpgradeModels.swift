import Foundation

enum UpgradeKind: String, Codable, Equatable, Hashable {
    case bitMultiplier
    case bondDividend
    case trickle
}

struct AgentUpgradeState: Codable, Equatable {
    var bitMultiplierLevel: Int
    var bondDividendLevel: Int
    var trickleLevel: Int
    var spentBits: Double
    var lastPurchasedAt: Date?
    var trickleBitsAccumulated: Double
    var bonusAccumulated: Double
    var lastTrickleAt: Date?

    init(
        bitMultiplierLevel: Int = 0,
        bondDividendLevel: Int = 0,
        trickleLevel: Int = 0,
        spentBits: Double = 0,
        lastPurchasedAt: Date? = nil,
        trickleBitsAccumulated: Double = 0,
        bonusAccumulated: Double = 0,
        lastTrickleAt: Date? = nil
    ) {
        self.bitMultiplierLevel = bitMultiplierLevel
        self.bondDividendLevel = bondDividendLevel
        self.trickleLevel = trickleLevel
        self.spentBits = spentBits
        self.lastPurchasedAt = lastPurchasedAt
        self.trickleBitsAccumulated = trickleBitsAccumulated
        self.bonusAccumulated = bonusAccumulated
        self.lastTrickleAt = lastTrickleAt
    }

    // Backward-compatible: existing economy.json may lack new keys.
    // bonusAccumulated = 0 on first decode → migration seeds it from retroactive bonus.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bitMultiplierLevel = (try? c.decode(Int.self, forKey: .bitMultiplierLevel)) ?? 0
        bondDividendLevel = (try? c.decode(Int.self, forKey: .bondDividendLevel)) ?? 0
        trickleLevel = (try? c.decode(Int.self, forKey: .trickleLevel)) ?? 0
        spentBits = (try? c.decode(Double.self, forKey: .spentBits)) ?? 0
        lastPurchasedAt = try? c.decode(Date.self, forKey: .lastPurchasedAt)
        trickleBitsAccumulated = (try? c.decode(Double.self, forKey: .trickleBitsAccumulated)) ?? 0
        bonusAccumulated = (try? c.decode(Double.self, forKey: .bonusAccumulated)) ?? 0
        lastTrickleAt = try? c.decode(Date.self, forKey: .lastTrickleAt)
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

    static var empty: UpgradeState { UpgradeState() }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = (try? c.decode([String: AgentUpgradeState].self, forKey: .agents)) ?? [:]
        lastUpdated = (try? c.decode(Date.self, forKey: .lastUpdated)) ?? Date(timeIntervalSince1970: 0)
    }
}

enum UpgradeEconomy {
    static let bitMultiplierBaseCost: Double = 50
    static let bitMultiplierCostGrowth: Double = 1.8

    // Bond Dividend: 3 levels. Multiplier = 1 + (bond/10) * factor.
    // At low bond, weaker than bitMultiplier. At bond 8+, significantly better.
    static let bondDividendCosts: [Double] = [200, 600, 1800]
    static let bondDividendFactors: [Double] = [0, 0.5, 1.2, 3.0]

    // Bit Trickle: Cookie Clicker cursor model. Each purchase adds 1 unit (+1 bit/10s).
    // Cost scales exponentially per unit owned. No level cap.
    static let trickleBaseCost: Double = 50
    static let trickleCostGrowth: Double = 1.15
    static let trickleRatePerUnit: Double = 1.0  // bits per 10s per unit

    static func cost(for upgrade: UpgradeKind, currentLevel: Int) -> Double {
        switch upgrade {
        case .bitMultiplier:
            return bitMultiplierBaseCost * pow(bitMultiplierCostGrowth, Double(currentLevel))
        case .bondDividend:
            guard currentLevel < bondDividendCosts.count else { return .infinity }
            return bondDividendCosts[currentLevel]
        case .trickle:
            return trickleBaseCost * pow(trickleCostGrowth, Double(currentLevel))
        }
    }

    // Bond dividend's bonus contribution (0.0 when locked, scales with bond).
    // Combined with bitMultiplier additively: effective = 1 + bitBonus + bdBonus.
    static func bondDividendMultiplier(level: Int, bond: Int) -> Double {
        guard level > 0, level < bondDividendFactors.count else { return 1.0 }
        return 1.0 + Double(bond) / 10.0 * bondDividendFactors[level]
    }

    // Additive combined multiplier: bonuses stack, not compound.
    // Prevents multiplicative explosion when both upgrades are purchased.
    static func effectiveMultiplier(bitMultiplier: Double, bdLevel: Int, bond: Int) -> Double {
        let bitBonus = bitMultiplier - 1.0
        let bdBonus = bondDividendMultiplier(level: bdLevel, bond: bond) - 1.0
        return 1.0 + bitBonus + bdBonus
    }

    // Returns bits per 10s for a given number of trickle units owned.
    static func trickleRate(count: Int) -> Double {
        Double(count) * trickleRatePerUnit
    }

    // availableBits = totalBits(raw) + bonusAccumulated + trickleAccumulated − spent
    // Multipliers only apply to new daemon events via bonusAccumulated, not retroactively.
    static func availableBits(for agentName: String, ledger: LedgerState, upgrades: UpgradeState) -> Double {
        guard let agent = ledger.agents[agentName] else { return 0 }
        let state = upgrades.agents[agentName]
        let spent = state?.spentBits ?? 0
        let trickle = state?.trickleBitsAccumulated ?? 0
        let bonus = state?.bonusAccumulated ?? 0
        return max(0, agent.totalBitsRaw + bonus + trickle - spent)
    }


    @discardableResult
    static func apply(_ upgrade: UpgradeKind, for agentName: String, ledger: LedgerState, upgrades: inout UpgradeState) -> Bool {
        var agentState = upgrades.agents[agentName] ?? AgentUpgradeState()
        let currentLevel: Int
        switch upgrade {
        case .bitMultiplier: currentLevel = agentState.bitMultiplierLevel
        case .bondDividend:  currentLevel = agentState.bondDividendLevel
        case .trickle:       currentLevel = agentState.trickleLevel
        }
        let upgradeCost = cost(for: upgrade, currentLevel: currentLevel)
        guard upgradeCost < .infinity,
              availableBits(for: agentName, ledger: ledger, upgrades: upgrades) >= upgradeCost
        else { return false }
        switch upgrade {
        case .bitMultiplier: agentState.bitMultiplierLevel += 1
        case .bondDividend:  agentState.bondDividendLevel += 1
        case .trickle:       agentState.trickleLevel += 1
        }
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
