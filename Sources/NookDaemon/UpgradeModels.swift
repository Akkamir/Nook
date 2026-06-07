import Foundation

enum UpgradeKind: String, Codable {
    case bitMultiplier
}

struct UpgradePurchaseRequest: Codable {
    let agentName: String
    let upgrade: UpgradeKind
    let requestedAt: Date
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
    var processedRequestCount: Int
    var lastUpdated: Date

    init(agents: [String: AgentUpgradeState], processedRequestCount: Int, lastUpdated: Date) {
        self.agents = agents
        self.processedRequestCount = processedRequestCount
        self.lastUpdated = lastUpdated
    }

    static var empty: UpgradeState {
        UpgradeState(agents: [:], processedRequestCount: 0, lastUpdated: Date(timeIntervalSince1970: 0))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = (try? c.decode([String: AgentUpgradeState].self, forKey: .agents)) ?? [:]
        processedRequestCount = (try? c.decode(Int.self, forKey: .processedRequestCount)) ?? 0
        lastUpdated = (try? c.decode(Date.self, forKey: .lastUpdated)) ?? Date(timeIntervalSince1970: 0)
    }
}

enum UpgradePurchaseResult: Equatable {
    case accepted
    case rejectedUnknownAgent
    case rejectedInsufficientBits
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

    static func multiplier(for agentName: String?, upgrades: UpgradeState) -> Double {
        guard let agentName else { return 1.0 }
        return upgrades.agents[agentName]?.bitMultiplier ?? 1.0
    }

    static func apply(
        request: UpgradePurchaseRequest,
        ledger: LedgerState,
        upgrades: inout UpgradeState
    ) -> UpgradePurchaseResult {
        guard ledger.agents[request.agentName] != nil else { return .rejectedUnknownAgent }

        var agentUpgrades = upgrades.agents[request.agentName] ?? AgentUpgradeState()
        let currentLevel: Int
        switch request.upgrade {
        case .bitMultiplier:
            currentLevel = agentUpgrades.bitMultiplierLevel
        }
        let cost = Self.cost(for: request.upgrade, currentLevel: currentLevel)
        guard availableBits(for: request.agentName, ledger: ledger, upgrades: upgrades) >= cost else {
            return .rejectedInsufficientBits
        }

        switch request.upgrade {
        case .bitMultiplier:
            agentUpgrades.bitMultiplierLevel += 1
        }
        agentUpgrades.spentBits += cost
        agentUpgrades.lastPurchasedAt = request.requestedAt
        upgrades.agents[request.agentName] = agentUpgrades
        upgrades.lastUpdated = Date()
        return .accepted
    }
}

final class UpgradeStore {
    private let stateURL: URL
    private let requestsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(stateURL: URL, requestsURL: URL) {
        self.stateURL = stateURL
        self.requestsURL = requestsURL
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> UpgradeState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? decoder.decode(UpgradeState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: UpgradeState) throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    func processRequests(ledger: LedgerState, upgrades: inout UpgradeState) throws -> [UpgradePurchaseResult] {
        guard let data = try? Data(contentsOf: requestsURL),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard upgrades.processedRequestCount < lines.count else { return [] }

        var results: [UpgradePurchaseResult] = []
        for line in lines.dropFirst(upgrades.processedRequestCount) {
            guard let lineData = String(line).data(using: .utf8),
                  let request = try? decoder.decode(UpgradePurchaseRequest.self, from: lineData)
            else {
                upgrades.processedRequestCount += 1
                continue
            }
            results.append(UpgradeEconomy.apply(request: request, ledger: ledger, upgrades: &upgrades))
            upgrades.processedRequestCount += 1
        }
        try save(upgrades)
        return results
    }
}

extension UpgradeStore {
    static var production: UpgradeStore {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelvillage")
        return UpgradeStore(
            stateURL: dir.appendingPathComponent("upgrades.json"),
            requestsURL: dir.appendingPathComponent("upgrade-requests.jsonl")
        )
    }
}
