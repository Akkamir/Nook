import Foundation

enum TranscriptParser {
    private struct RawLine: Decodable {
        let message: Message?

        struct Message: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    static func parseLine(_ line: String) -> TokenEvent? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              let usage = raw.message?.usage
        else { return nil }

        return TokenEvent(
            projectPath: "",
            inputTokens: usage.input_tokens,
            outputTokens: usage.output_tokens,
            timestamp: Date()
        )
    }
}
