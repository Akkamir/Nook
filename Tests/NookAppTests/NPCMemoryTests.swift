import XCTest
@testable import Nook

final class NPCMemoryTests: XCTestCase {
    func test_heuristic_session_title_uses_task_theme_and_project() {
        let session = SessionRecord(
            sessionId: "s1",
            project: "Nook",
            projectPath: "/p/Nook",
            agentName: "Radion",
            startedAt: Date(),
            lastActivityAt: Date(),
            inputTokens: 0,
            outputTokens: 0,
            totalBits: 0,
            task: "implement NPC memory and narration",
            filesTouched: ["Sources/NookApp/NPCMemory.swift"]
        )

        XCTAssertEqual(GeneratedSessionMemory.heuristic(for: session).title, "Implement NPC memory · Nook")
    }

    func test_memory_store_round_trips_cached_session_memory() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("npc-memory.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = NPCMemoryStore(url: url)
        let memory = GeneratedSessionMemory(
            sessionId: "s1",
            agentName: "Radion",
            title: "Shop work · Nook",
            shortSummary: "Worked on upgrades.",
            narrativeBeats: ["Bought a multiplier"],
            relationshipNote: "More confident together",
            cachedLines: ["This is starting to feel like our thing."],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        try store.save(NPCMemoryState(sessions: ["s1": memory]))
        let loaded = store.load()

        XCTAssertEqual(loaded.sessions["s1"]?.title, "Shop work · Nook")
        XCTAssertEqual(loaded.sessions["s1"]?.cachedLines.first, "This is starting to feel like our thing.")
    }

    func test_transcript_digest_extracts_concrete_signals_and_bounds_content() {
        let longPrompt = String(repeating: "make the narration specific ", count: 40)
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"\(longPrompt)"},"cwd":"/Users/me/Nook","gitBranch":"main"}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/Users/me/Nook/Sources/NookApp/ContentView.swift"}},{"type":"tool_use","name":"Bash","input":{"command":"swift test --filter NPCMemoryTests"}}]}}
        """

        let digest = SessionDigest.fromTranscript(jsonl, project: "Nook", maxTextLength: 120)

        XCTAssertEqual(digest.project, "Nook")
        XCTAssertEqual(digest.files, ["ContentView.swift"])
        XCTAssertEqual(digest.commands, ["swift"])
        XCTAssertLessThanOrEqual(digest.recentUserAsks.joined().count, 120)
    }
}
