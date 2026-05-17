import Foundation

enum AgentAttributor {
    private struct Config: Decodable {
        let agent: String?
    }

    static func agentName(forProjectPath path: String) -> String? {
        let configURL = URL(fileURLWithPath: path)
            .appendingPathComponent(".pixelvillage")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }
        return config.agent
    }
}
