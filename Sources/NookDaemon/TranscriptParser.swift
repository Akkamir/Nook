import Foundation

struct ToolUse: Equatable {
    let name: String
    let filePath: String?
    let command: String?
}

struct ParsedEntry {
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let cwd: String?
    let gitBranch: String?
    let role: String?
    let userText: String?
    let toolUses: [ToolUse]
}

enum TranscriptParser {
    private struct RawLine: Decodable {
        let cwd: String?
        let gitBranch: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let role: String?
            let usage: Usage?
            let content: Content?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }

        struct Block: Decodable {
            let type: String?
            let text: String?
            let name: String?
            let input: Input?
        }

        struct Input: Decodable {
            let file_path: String?
            let command: String?
        }

        // message.content is either a String or an array of blocks.
        enum Content: Decodable {
            case text(String)
            case blocks([Block])

            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) {
                    self = .text(s)
                } else {
                    self = .blocks((try? c.decode([Block].self)) ?? [])
                }
            }
        }
    }

    static func parseLine(_ line: String) -> ParsedEntry? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              let message = raw.message
        else { return nil }

        let iso = ISO8601DateFormatter()
        let timestamp = raw.timestamp.flatMap { iso.date(from: $0) } ?? Date()

        var userText: String?
        var toolUses: [ToolUse] = []
        switch message.content {
        case .text(let s):
            if message.role == "user" { userText = s }
        case .blocks(let blocks):
            if message.role == "user" {
                userText = blocks.first(where: { $0.type == "text" })?.text
            }
            if message.role == "assistant" {
                toolUses = blocks.compactMap { b in
                    guard b.type == "tool_use", let name = b.name else { return nil }
                    return ToolUse(name: name, filePath: b.input?.file_path, command: b.input?.command)
                }
            }
        case .none:
            break
        }

        return ParsedEntry(
            inputTokens: message.usage?.input_tokens ?? 0,
            outputTokens: message.usage?.output_tokens ?? 0,
            timestamp: timestamp,
            cwd: raw.cwd,
            gitBranch: raw.gitBranch,
            role: message.role,
            userText: userText,
            toolUses: toolUses
        )
    }
}
