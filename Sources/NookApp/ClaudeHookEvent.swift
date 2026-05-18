import Foundation

struct ClaudeHookEvent: Decodable {
    let name: String
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let source: String?
    let reason: String?
    let notificationType: String?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case name = "hook_event_name"
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case source
        case reason
        case notificationType = "notification_type"
        case toolName = "tool_name"
    }

    var isSessionStart: Bool { name == "SessionStart" }
    var isSessionEnd: Bool { name == "SessionEnd" }
    var refreshesActivity: Bool {
        ["PreToolUse", "PostToolUse", "Stop", "Notification"].contains(name)
    }
}

struct ClaudeHookServerConfig: Codable {
    let port: Int
    let token: String
}
