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
            return [
                "On it: \(p)",
                "New mission — \(p)",
                "Alright, let's go.",
                "Reading the brief: \(p)",
            ].randomElement()!
        case "file":
            guard let p = event.payload else { return nil }
            return [
                "Deep in \(p)",
                "I see \(p)",
                "Oh, \(p)…",
                "Opening \(p)",
            ].randomElement()!
        case "testing":
            return [
                "Love a good test run.",
                "Tests time?",
                "Red or green?",
                "Running the suite.",
            ].randomElement()!
        case "committing":
            return [
                "Committing?",
                "Checkpoint.",
                "Good call.",
                "Git commit incoming.",
            ].randomElement()!
        case "deepWork":
            guard let p = event.payload else { return nil }
            return [
                "Heavy session on \(p)",
                "We're really in it.",
                "Long run on \(p).",
                "Nice progress.",
            ].randomElement()!
        default:
            return nil
        }
    }
}
