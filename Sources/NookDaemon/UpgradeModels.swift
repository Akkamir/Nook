import Foundation

// Minimal read-only view of economy.json — the app is the authoritative writer.
final class EconomyReader {
    private let url: URL

    init(url: URL) { self.url = url }

    func multiplier(for agentName: String?) -> Double {
        guard let agentName,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(EconomySnapshot.self, from: data)
        else { return 1.0 }
        return snapshot.agents[agentName]?.bitMultiplier ?? 1.0
    }

    static var production: EconomyReader {
        EconomyReader(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/economy.json"))
    }
}

private struct EconomySnapshot: Codable {
    struct AgentEconomy: Codable {
        var bitMultiplierLevel: Int

        var bitMultiplier: Double { 1.0 + Double(bitMultiplierLevel) * 0.25 }

        init(bitMultiplierLevel: Int = 0) {
            self.bitMultiplierLevel = bitMultiplierLevel
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bitMultiplierLevel = (try? c.decode(Int.self, forKey: .bitMultiplierLevel)) ?? 0
        }
    }

    var agents: [String: AgentEconomy]

    init(agents: [String: AgentEconomy] = [:]) {
        self.agents = agents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = (try? c.decode([String: AgentEconomy].self, forKey: .agents)) ?? [:]
    }
}
