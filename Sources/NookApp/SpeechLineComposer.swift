import Foundation

protocol SpeechLineComposing {
    func line(for event: SessionActivityEvent, session: SessionRecord?) -> String?
}

/// Heuristic, deterministic, local composer. Returns nil to say nothing.
/// A future LLMLineComposer can implement the same protocol without touching
/// detection (daemon) or rendering (sprite).
struct HeuristicLineComposer: SpeechLineComposing {
    func line(for event: SessionActivityEvent, session: SessionRecord?) -> String? {
        switch event.kind {
        case "task":
            guard let p = event.payload else { return nil }
            return "On attaque : \(p)"
        case "file":
            guard let p = event.payload else { return nil }
            return "Plongé dans \(p)"
        case "testing":
            return "TDD, j'aime ça"
        case "committing":
            return "On commit ?"
        case "deepWork":
            guard let p = event.payload else { return nil }
            return "Grosse session sur \(p)"
        default:
            return nil
        }
    }
}
