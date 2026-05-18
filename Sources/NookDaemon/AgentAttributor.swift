import Foundation

enum AgentAttributor {
    private struct Config: Decodable {
        let agent: String?
    }

    static func agentName(forProjectPath path: String) -> String? {
        // First try the real project directory by decoding the encoded dir name
        let dirName = URL(fileURLWithPath: path).lastPathComponent
        if dirName.hasPrefix("-") {
            let realPath = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")
            if let agent = readAgent(at: URL(fileURLWithPath: realPath)) {
                return agent
            }
        }
        // Fallback: look directly in the Claude project dir
        return readAgent(at: URL(fileURLWithPath: path))
    }

    private static func readAgent(at url: URL) -> String? {
        let configURL = url.appendingPathComponent(".pixelvillage")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }
        return config.agent
    }
}
