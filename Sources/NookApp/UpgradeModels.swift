import Foundation

enum UpgradeKind: String, Codable, Equatable, Hashable {
    case bitMultiplier
    case bondDividend
    case trickle
}

struct EconomyMigrationState: Codable, Equatable {
    var adjustedAt: Date?
    var note: String?

    init(adjustedAt: Date? = nil, note: String? = nil) {
        self.adjustedAt = adjustedAt
        self.note = note
    }
}

struct AgentEconomyState: Codable, Equatable {
    var wallet: Double
    var spentBits: Double
    var lastProcessedRawBits: Double
    var bitMultiplierLevel: Int
    var bondDividendLevel: Int
    var trickleCount: Int
    var trickleBitsAccumulated: Double
    var lastPurchasedAt: Date?
    var lastTrickleAt: Date?
    var migrationAdjusted: Bool

    init(wallet: Double = 0, spentBits: Double = 0, lastProcessedRawBits: Double = 0,
         bitMultiplierLevel: Int = 0, bondDividendLevel: Int = 0, trickleCount: Int = 0,
         trickleBitsAccumulated: Double = 0, lastPurchasedAt: Date? = nil,
         lastTrickleAt: Date? = nil, migrationAdjusted: Bool = false) {
        self.wallet = wallet
        self.spentBits = spentBits
        self.lastProcessedRawBits = lastProcessedRawBits
        self.bitMultiplierLevel = bitMultiplierLevel
        self.bondDividendLevel = bondDividendLevel
        self.trickleCount = trickleCount
        self.trickleBitsAccumulated = trickleBitsAccumulated
        self.lastPurchasedAt = lastPurchasedAt
        self.lastTrickleAt = lastTrickleAt
        self.migrationAdjusted = migrationAdjusted
    }

    enum CodingKeys: String, CodingKey {
        case wallet, spentBits, lastProcessedRawBits, bitMultiplierLevel, bondDividendLevel
        case trickleCount, trickleLevel, trickleBitsAccumulated, lastPurchasedAt, lastTrickleAt
        case migrationAdjusted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wallet = (try? c.decode(Double.self, forKey: .wallet)) ?? 0
        spentBits = (try? c.decode(Double.self, forKey: .spentBits)) ?? 0
        lastProcessedRawBits = (try? c.decode(Double.self, forKey: .lastProcessedRawBits)) ?? 0
        bitMultiplierLevel = (try? c.decode(Int.self, forKey: .bitMultiplierLevel)) ?? 0
        bondDividendLevel = (try? c.decode(Int.self, forKey: .bondDividendLevel)) ?? 0
        trickleCount = (try? c.decode(Int.self, forKey: .trickleCount))
            ?? ((try? c.decode(Int.self, forKey: .trickleLevel)) ?? 0)
        trickleBitsAccumulated = (try? c.decode(Double.self, forKey: .trickleBitsAccumulated)) ?? 0
        lastPurchasedAt = try? c.decode(Date.self, forKey: .lastPurchasedAt)
        lastTrickleAt = try? c.decode(Date.self, forKey: .lastTrickleAt)
        migrationAdjusted = (try? c.decode(Bool.self, forKey: .migrationAdjusted)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wallet, forKey: .wallet)
        try c.encode(spentBits, forKey: .spentBits)
        try c.encode(lastProcessedRawBits, forKey: .lastProcessedRawBits)
        try c.encode(bitMultiplierLevel, forKey: .bitMultiplierLevel)
        try c.encode(bondDividendLevel, forKey: .bondDividendLevel)
        try c.encode(trickleCount, forKey: .trickleCount)
        try c.encode(trickleBitsAccumulated, forKey: .trickleBitsAccumulated)
        try c.encodeIfPresent(lastPurchasedAt, forKey: .lastPurchasedAt)
        try c.encodeIfPresent(lastTrickleAt, forKey: .lastTrickleAt)
        try c.encode(migrationAdjusted, forKey: .migrationAdjusted)
    }

    var availableBits: Double { max(0, wallet + trickleBitsAccumulated - spentBits) }
}

typealias AgentUpgradeState = AgentEconomyState

struct EconomyState: Codable, Equatable {
    var schemaVersion: Int
    var agents: [String: AgentEconomyState]
    var villageWallet: Double
    var spentVillageBits: Double
    var lastProcessedGlobalRawBits: Double
    var lastUpdated: Date
    var migration: EconomyMigrationState

    init(schemaVersion: Int = EconomyEngine.currentSchemaVersion,
         agents: [String: AgentEconomyState] = [:],
         villageWallet: Double = 0,
         spentVillageBits: Double = 0,
         lastProcessedGlobalRawBits: Double = 0,
         lastUpdated: Date = Date(timeIntervalSince1970: 0),
         migration: EconomyMigrationState = EconomyMigrationState()) {
        self.schemaVersion = schemaVersion
        self.agents = agents
        self.villageWallet = villageWallet
        self.spentVillageBits = spentVillageBits
        self.lastProcessedGlobalRawBits = lastProcessedGlobalRawBits
        self.lastUpdated = lastUpdated
        self.migration = migration
    }

    static var empty: EconomyState { EconomyState() }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, agents, villageWallet, spentVillageBits, lastProcessedGlobalRawBits, lastUpdated, migration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        agents = (try? c.decode([String: AgentEconomyState].self, forKey: .agents)) ?? [:]
        villageWallet = (try? c.decode(Double.self, forKey: .villageWallet)) ?? 0
        spentVillageBits = (try? c.decode(Double.self, forKey: .spentVillageBits)) ?? 0
        lastProcessedGlobalRawBits = (try? c.decode(Double.self, forKey: .lastProcessedGlobalRawBits)) ?? 0
        lastUpdated = (try? c.decode(Date.self, forKey: .lastUpdated)) ?? Date(timeIntervalSince1970: 0)
        migration = (try? c.decode(EconomyMigrationState.self, forKey: .migration)) ?? EconomyMigrationState()
    }

    var villageAvailableBits: Double { max(0, villageWallet - spentVillageBits) }
}

typealias UpgradeState = EconomyState

enum EconomyEngine {
    static let currentSchemaVersion = 2
    static let villageBonusRate = 0.10
    static let bitMultiplierBonuses: [Double] = [0, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00]
    static let bitMultiplierCosts: [Double] = [500, 1_250, 3_000, 7_500, 18_000, 45_000]
    static let bondDividendGates: [Int] = [0, 3, 6, 10]
    static let bondDividendFactors: [Double] = [0, 0.03, 0.06, 0.10]
    static let bondDividendCosts: [Double] = [1_500, 6_000, 20_000]
    static let trickleBaseCost: Double = 100
    static let trickleCostGrowth: Double = 1.25
    static let trickleRatePerUnit: Double = 0.25

    static func bitMultiplierBonus(level: Int) -> Double {
        guard level >= 0 else { return 0 }
        return bitMultiplierBonuses[min(level, bitMultiplierBonuses.count - 1)]
    }

    static func bondDividendBonus(level: Int, bond: Int) -> Double {
        guard level > 0, level < bondDividendFactors.count else { return 0 }
        return Double(bond) * bondDividendFactors[level]
    }

    static func effectiveMultiplier(for state: AgentEconomyState, bond: Int) -> Double {
        1.0 + bitMultiplierBonus(level: state.bitMultiplierLevel)
            + bondDividendBonus(level: state.bondDividendLevel, bond: bond)
    }

    static func trickleRate(count: Int) -> Double {
        Double(max(0, count)) * trickleRatePerUnit
    }

    static func trickleCap(forBond bond: Int) -> Int {
        switch bond {
        case ..<3: return 2
        case ..<6: return 5
        case ..<10: return 10
        default: return 20
        }
    }

    static func cost(for upgrade: UpgradeKind, currentLevel: Int) -> Double {
        switch upgrade {
        case .bitMultiplier:
            guard currentLevel < bitMultiplierCosts.count else { return .infinity }
            return bitMultiplierCosts[currentLevel]
        case .bondDividend:
            guard currentLevel < bondDividendCosts.count else { return .infinity }
            return bondDividendCosts[currentLevel]
        case .trickle:
            return trickleBaseCost * pow(trickleCostGrowth, Double(currentLevel))
        }
    }

    static func canBuy(_ upgrade: UpgradeKind, currentLevel: Int, bond: Int) -> Bool {
        switch upgrade {
        case .bitMultiplier:
            return currentLevel < bitMultiplierCosts.count
        case .bondDividend:
            let next = currentLevel + 1
            guard next < bondDividendGates.count else { return false }
            return bond >= bondDividendGates[next]
        case .trickle:
            return currentLevel < trickleCap(forBond: bond)
        }
    }

    static func processLedgerDelta(ledger: LedgerState, economy: inout EconomyState) {
        if economy.schemaVersion < currentSchemaVersion {
            economy = migratedState(from: economy, ledger: ledger)
        }

        for (agentName, ledgerAgent) in ledger.agents {
            var state = economy.agents[agentName] ?? AgentEconomyState()
            let rawDelta = ledgerAgent.totalBitsRaw - state.lastProcessedRawBits
            if rawDelta > 0 {
                let effective = rawDelta * effectiveMultiplier(for: state, bond: ledgerAgent.bond)
                state.wallet += effective
                state.lastProcessedRawBits = ledgerAgent.totalBitsRaw
                economy.villageWallet += effective * villageBonusRate
            } else if rawDelta < 0 {
                state.lastProcessedRawBits = ledgerAgent.totalBitsRaw
            }
            economy.agents[agentName] = state
        }

        let globalDelta = ledger.globalBitsRaw - economy.lastProcessedGlobalRawBits
        if globalDelta > 0 {
            economy.villageWallet += globalDelta
            economy.lastProcessedGlobalRawBits = ledger.globalBitsRaw
        } else if globalDelta < 0 {
            economy.lastProcessedGlobalRawBits = ledger.globalBitsRaw
        }

        economy.lastUpdated = Date()
    }

    static func migratedState(from old: EconomyState, ledger: LedgerState) -> EconomyState {
        var migrated = old
        migrated.schemaVersion = currentSchemaVersion
        migrated.lastProcessedGlobalRawBits = ledger.globalBitsRaw
        migrated.migration = EconomyMigrationState(adjustedAt: Date(), note: "Conservative economy migration")

        for (agentName, ledgerAgent) in ledger.agents {
            var agent = migrated.agents[agentName] ?? AgentEconomyState()
            agent.wallet = conservativeStartingWallet(rawBits: ledgerAgent.totalBitsRaw, bond: ledgerAgent.bond)
            agent.spentBits = 0
            agent.lastProcessedRawBits = ledgerAgent.totalBitsRaw
            agent.bitMultiplierLevel = min(max(agent.bitMultiplierLevel, 0), bitMultiplierBonuses.count - 1)
            agent.bondDividendLevel = validBondDividendLevel(agent.bondDividendLevel, bond: ledgerAgent.bond)
            agent.trickleCount = min(max(agent.trickleCount, 0), trickleCap(forBond: ledgerAgent.bond))
            agent.migrationAdjusted = true
            migrated.agents[agentName] = agent
        }

        return migrated
    }

    static func conservativeStartingWallet(rawBits: Double, bond: Int) -> Double {
        min(rawBits * 0.25, walletCap(forBond: bond))
    }

    static func walletCap(forBond bond: Int) -> Double {
        switch bond {
        case ..<3: return 500
        case ..<6: return 1_500
        case ..<10: return 5_000
        default: return 12_000
        }
    }

    static func validBondDividendLevel(_ level: Int, bond: Int) -> Int {
        let clamped = min(max(level, 0), bondDividendGates.count - 1)
        var valid = 0
        for candidate in 0...clamped where bond >= bondDividendGates[candidate] {
            valid = candidate
        }
        return valid
    }

    @discardableResult
    static func apply(_ upgrade: UpgradeKind, for agentName: String, ledger: LedgerState, economy: inout EconomyState) -> Bool {
        guard let ledgerAgent = ledger.agents[agentName] else { return false }
        var state = economy.agents[agentName] ?? AgentEconomyState()

        let currentLevel: Int
        switch upgrade {
        case .bitMultiplier: currentLevel = state.bitMultiplierLevel
        case .bondDividend: currentLevel = state.bondDividendLevel
        case .trickle: currentLevel = state.trickleCount
        }

        guard canBuy(upgrade, currentLevel: currentLevel, bond: ledgerAgent.bond) else { return false }
        let upgradeCost = cost(for: upgrade, currentLevel: currentLevel)
        guard upgradeCost < .infinity, state.availableBits >= upgradeCost else { return false }

        switch upgrade {
        case .bitMultiplier: state.bitMultiplierLevel += 1
        case .bondDividend: state.bondDividendLevel += 1
        case .trickle: state.trickleCount += 1
        }

        state.spentBits += upgradeCost
        state.lastPurchasedAt = Date()
        economy.agents[agentName] = state
        economy.lastUpdated = Date()
        return true
    }
}

enum UpgradeEconomy {
    static func cost(for upgrade: UpgradeKind, currentLevel: Int) -> Double {
        EconomyEngine.cost(for: upgrade, currentLevel: currentLevel)
    }

    static func trickleRate(count: Int) -> Double {
        EconomyEngine.trickleRate(count: count)
    }

    static func availableBits(for agentName: String, ledger: LedgerState, upgrades: EconomyState) -> Double {
        upgrades.agents[agentName]?.availableBits ?? 0
    }

    static func bitMultiplierDisplay(level: Int) -> Double {
        1.0 + EconomyEngine.bitMultiplierBonus(level: level)
    }

    static func bondDividendMultiplier(level: Int, bond: Int) -> Double {
        1.0 + EconomyEngine.bondDividendBonus(level: level, bond: bond)
    }

    static func effectiveMultiplier(bitMultiplier: Double, bdLevel: Int, bond: Int) -> Double {
        let bitBonus = bitMultiplier - 1.0
        let bdBonus = EconomyEngine.bondDividendBonus(level: bdLevel, bond: bond)
        return 1.0 + bitBonus + bdBonus
    }

    @discardableResult
    static func apply(_ upgrade: UpgradeKind, for agentName: String, ledger: LedgerState, upgrades: inout EconomyState) -> Bool {
        EconomyEngine.apply(upgrade, for: agentName, ledger: ledger, economy: &upgrades)
    }
}

extension AgentEconomyState {
    var bitMultiplier: Double {
        UpgradeEconomy.bitMultiplierDisplay(level: bitMultiplierLevel)
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

    func load() -> EconomyState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(EconomyState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: EconomyState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    static var production: EconomyStore {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelvillage")
        return EconomyStore(url: dir.appendingPathComponent("economy.json"))
    }
}
