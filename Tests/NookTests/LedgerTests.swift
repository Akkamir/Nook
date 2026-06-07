import XCTest
@testable import NookDaemon

final class LedgerTests: XCTestCase {

    var ledgerURL: URL!
    var ledger: Ledger!

    override func setUp() {
        super.setUp()
        ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ledger.json")
        ledger = Ledger(url: ledgerURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ledgerURL.deletingLastPathComponent())
        super.tearDown()
    }

    func test_load_returns_empty_state_when_no_file() {
        let state = ledger.load()
        XCTAssertEqual(state.totalBits, 0)
        XCTAssertEqual(state.pendingBits, 0)
        XCTAssertTrue(state.agents.isEmpty)
    }

    func test_save_and_reload_preserves_state() throws {
        var state = LedgerState.empty
        state.totalBits = 42.5
        state.pendingBits = 10.0
        state.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 1_856_640, bond: 3)

        try ledger.save(state)
        let loaded = ledger.load()

        XCTAssertEqual(loaded.totalBits, 42.5, accuracy: 0.001)
        XCTAssertEqual(loaded.pendingBits, 10.0, accuracy: 0.001)
        XCTAssertEqual(loaded.agents["Radion"]?.totalTokens, 1_856_640)
        XCTAssertEqual(loaded.agents["Radion"]?.bond, 5)
    }

    func test_apply_event_global_pool_increases_bits() throws {
        let event = TokenEvent(
            sessionId: "t", projectPath: "/some/project", cwd: nil,
            inputTokens: 1000,
            outputTokens: 1000,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: nil, to: &state)

        // 1000 input *5/1000 + 1000 output *5 *5/1000 = 5 + 25 = 30 Bits
        XCTAssertEqual(state.pendingBits, 30.0, accuracy: 0.001)
        XCTAssertEqual(state.totalBits, 30.0, accuracy: 0.001)
        XCTAssertTrue(state.agents.isEmpty)
    }

    func test_apply_event_with_agent_updates_bond() throws {
        let event = TokenEvent(
            sessionId: "t", projectPath: "/some/project", cwd: nil,
            inputTokens: 400_000,
            outputTokens: 0,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: "Radion", to: &state)

        XCTAssertEqual(state.agents["Radion"]?.totalTokens, 400_000)
        XCTAssertEqual(state.agents["Radion"]?.bond, 2)
    }

    func test_apply_event_uses_twenty_level_bond_scale() throws {
        let event = TokenEvent(
            sessionId: "t", projectPath: "/some/project", cwd: nil,
            inputTokens: 1_856_640,
            outputTokens: 0,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: "Radion", to: &state)

        XCTAssertEqual(state.agents["Radion"]?.bond, 5)
    }

    func test_apply_creates_session_record_on_first_event() {
        var state = LedgerState.empty
        let event = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/Users/me/Code/Nook",
                               inputTokens: 100, outputTokens: 200, timestamp: date("2026-06-01T10:00:00Z"))
        ledger.apply(event: event, agentName: "Radion", to: &state)

        let s = state.sessions["s1"]
        XCTAssertEqual(s?.project, "Nook")
        XCTAssertEqual(s?.agentName, "Radion")
        XCTAssertEqual(s?.totalTokens, 1_100)
        XCTAssertEqual(s?.startedAt, date("2026-06-01T10:00:00Z"))
        XCTAssertEqual(s?.lastActivityAt, date("2026-06-01T10:00:00Z"))
    }

    func test_apply_updates_session_record_on_subsequent_event() {
        var state = LedgerState.empty
        let e1 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/Users/me/Code/Nook",
                            inputTokens: 100, outputTokens: 200, timestamp: date("2026-06-01T10:00:00Z"))
        let e2 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/Users/me/Code/Nook",
                            inputTokens: 50, outputTokens: 50, timestamp: date("2026-06-01T11:00:00Z"))
        ledger.apply(event: e1, agentName: "Radion", to: &state)
        ledger.apply(event: e2, agentName: "Radion", to: &state)

        let s = state.sessions["s1"]
        XCTAssertEqual(s?.totalTokens, 1_400)
        XCTAssertEqual(s?.startedAt, date("2026-06-01T10:00:00Z"))
        XCTAssertEqual(s?.lastActivityAt, date("2026-06-01T11:00:00Z"))
        XCTAssertEqual(state.sessions.count, 1)
    }

    func test_apply_separate_session_ids_create_separate_records() {
        var state = LedgerState.empty
        let e1 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/c/Nook",
                            inputTokens: 100, outputTokens: 0, timestamp: date("2026-06-01T10:00:00Z"))
        let e2 = TokenEvent(sessionId: "s2", projectPath: "/p", cwd: "/c/Nook",
                            inputTokens: 100, outputTokens: 0, timestamp: date("2026-06-01T10:00:00Z"))
        ledger.apply(event: e1, agentName: "Radion", to: &state)
        ledger.apply(event: e2, agentName: "Radion", to: &state)
        XCTAssertEqual(state.sessions.count, 2)
    }

    func test_apply_nil_agent_does_not_clobber_prior_attribution() {
        var state = LedgerState.empty
        let e1 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/c/Nook",
                            inputTokens: 100, outputTokens: 0, timestamp: date("2026-06-01T10:00:00Z"))
        let e2 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/c/Nook",
                            inputTokens: 100, outputTokens: 0, timestamp: date("2026-06-01T11:00:00Z"))
        ledger.apply(event: e1, agentName: "Radion", to: &state)
        ledger.apply(event: e2, agentName: nil, to: &state)
        XCTAssertEqual(state.sessions["s1"]?.agentName, "Radion")
    }

    private func entry(role: String? = nil, userText: String? = nil, tools: [ToolUse] = [],
                       at: String = "2026-06-01T10:00:00Z") -> ParsedEntry {
        ParsedEntry(inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
                    timestamp: date(at), cwd: "/c/Nook",
                    gitBranch: "main", role: role, userText: userText, toolUses: tools)
    }

    func test_ingest_first_user_prompt_sets_task_and_emits_once() {
        var state = LedgerState.empty
        ledger.ingestSubject(entry: entry(role: "user", userText: "refactor auth"), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        XCTAssertEqual(state.sessions["s1"]?.task, "refactor auth")
        XCTAssertEqual(state.recentActivity.filter { $0.kind == "task" }.count, 1)
        ledger.ingestSubject(entry: entry(role: "user", userText: "now tests"), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        XCTAssertEqual(state.recentActivity.filter { $0.kind == "task" }.count, 1)
    }

    func test_ingest_new_file_emits_file_event_once() {
        var state = LedgerState.empty
        let tool = ToolUse(name: "Edit", filePath: "/c/Nook/Auth.swift", command: nil)
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [tool]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [tool]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        let fileEvents = state.recentActivity.filter { $0.kind == "file" }
        XCTAssertEqual(fileEvents.count, 1)
        XCTAssertEqual(fileEvents.first?.payload, "Auth.swift")
        XCTAssertEqual(state.sessions["s1"]?.editCount, 2)
    }

    func test_ingest_test_command_emits_testing_once_with_coarse_payload() {
        var state = LedgerState.empty
        let bash = ToolUse(name: "Bash", filePath: nil, command: "swift test --filter Foo")
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [bash]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [bash]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        let testing = state.recentActivity.filter { $0.kind == "testing" }
        XCTAssertEqual(testing.count, 1)
        XCTAssertEqual(testing.first?.payload, "swift")
    }

    func test_ingest_deepwork_fires_when_edit_count_crosses_ten() {
        var state = LedgerState.empty
        let tool = ToolUse(name: "Edit", filePath: nil, command: nil)
        for _ in 0..<10 {
            ledger.ingestSubject(entry: entry(role: "assistant", tools: [tool]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        }
        XCTAssertEqual(state.recentActivity.filter { $0.kind == "deepWork" }.count, 1)
    }

    private func date(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }
}
