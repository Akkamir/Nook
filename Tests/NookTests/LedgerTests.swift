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
        state.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 50_000, bond: 3)

        try ledger.save(state)
        let loaded = ledger.load()

        XCTAssertEqual(loaded.totalBits, 42.5, accuracy: 0.001)
        XCTAssertEqual(loaded.pendingBits, 10.0, accuracy: 0.001)
        XCTAssertEqual(loaded.agents["Radion"]?.totalTokens, 50_000)
        XCTAssertEqual(loaded.agents["Radion"]?.bond, 3)
    }

    func test_apply_event_global_pool_increases_bits() throws {
        let event = TokenEvent(
            projectPath: "/some/project",
            inputTokens: 1000,
            outputTokens: 1000,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: nil, to: &state)

        // 1000*5/1000 + 1000*15/1000 = 20 Bits
        XCTAssertEqual(state.pendingBits, 20.0, accuracy: 0.001)
        XCTAssertEqual(state.totalBits, 20.0, accuracy: 0.001)
        XCTAssertTrue(state.agents.isEmpty)
    }

    func test_apply_event_with_agent_updates_bond() throws {
        let event = TokenEvent(
            projectPath: "/some/project",
            inputTokens: 10_000,
            outputTokens: 0,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: "Radion", to: &state)

        XCTAssertEqual(state.agents["Radion"]?.totalTokens, 10_000)
        XCTAssertEqual(state.agents["Radion"]?.bond, 2)
    }
}
