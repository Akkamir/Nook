import Foundation

struct ParsedEntry {
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let cwd: String?
}

enum TranscriptParser {
    private struct RawLine: Decodable {
        let cwd: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    static func parseLine(_ line: String) -> ParsedEntry? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              let usage = raw.message?.usage
        else { return nil }

        let iso = ISO8601DateFormatter()
        let timestamp = raw.timestamp.flatMap { iso.date(from: $0) } ?? Date()

        return ParsedEntry(
            inputTokens: usage.input_tokens,
            outputTokens: usage.output_tokens,
            timestamp: timestamp,
            cwd: raw.cwd
        )
    }
}
