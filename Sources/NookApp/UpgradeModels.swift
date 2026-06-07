import Foundation

enum UpgradeKind: String, Codable, Equatable {
    case bitMultiplier
}

struct UpgradePurchaseRequest: Codable, Equatable {
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
}

final class UpgradeFileStore {
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

    func append(_ request: UpgradePurchaseRequest) throws {
        try FileManager.default.createDirectory(at: requestsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(request)
        var line = data
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: requestsURL.path) {
            let handle = try FileHandle(forWritingTo: requestsURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: requestsURL, options: .atomic)
        }
    }
}

extension UpgradeFileStore {
    static var production: UpgradeFileStore {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelvillage")
        return UpgradeFileStore(
            stateURL: dir.appendingPathComponent("upgrades.json"),
            requestsURL: dir.appendingPathComponent("upgrade-requests.jsonl")
        )
    }
}
