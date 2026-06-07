import XCTest
@testable import NookDaemon

final class UpgradeTests: XCTestCase {
    private var tempDir: URL!
    private var ledger: Ledger!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        ledger = Ledger(url: tempDir.appendingPathComponent("ledger.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Ledger.apply with multiplier

    func test_apply_uses_given_multiplier_for_attributed_agent() throws {
        var state = LedgerState.empty
        state.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 0, bond: 1, totalBits: 120)

        let event = TokenEvent(
            sessionId: "s1", projectPath: "/p", cwd: "/p",
            inputTokens: 1000, outputTokens: 1000,
            timestamp: date("2026-06-07T10:05:00Z")
        )
        // Base bits = 1000/1000*5 + 1000/1000*15 = 20. With 1.25x → 25.
        ledger.apply(event: event, agentName: "Radion", multiplier: 1.25, to: &state)

        XCTAssertEqual(try XCTUnwrap(state.agents["Radion"]).totalBits, 145, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.recentEvents.last).bits, 25, accuracy: 0.001)
    }

    func test_apply_multiplier_does_not_affect_other_agents() throws {
        var state = LedgerState.empty
        let event = TokenEvent(
            sessionId: "s2", projectPath: "/p", cwd: "/p",
            inputTokens: 1000, outputTokens: 1000,
            timestamp: date("2026-06-07T10:05:00Z")
        )
        // "Other" gets a 1.25x multiplier; "Radion" gets 1.0x
        ledger.apply(event: event, agentName: "Other", multiplier: 1.25, to: &state)
        ledger.apply(event: event, agentName: "Radion", multiplier: 1.0, to: &state)

        XCTAssertEqual(try XCTUnwrap(state.agents["Other"]).totalBits, 25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.agents["Radion"]).totalBits, 20, accuracy: 0.001)
    }

    func test_apply_defaults_to_1x_when_no_multiplier_given() throws {
        var state = LedgerState.empty
        let event = TokenEvent(
            sessionId: "s3", projectPath: "/p", cwd: "/p",
            inputTokens: 1000, outputTokens: 0,
            timestamp: date("2026-06-07T10:05:00Z")
        )
        // inputTokens/1000 * 5 = 5 bits, no multiplier
        ledger.apply(event: event, agentName: "Radion", to: &state)

        XCTAssertEqual(try XCTUnwrap(state.agents["Radion"]).totalBits, 5, accuracy: 0.001)
    }

    // MARK: - EconomyReader

    func test_economy_reader_returns_correct_multiplier_from_file() throws {
        let economyURL = tempDir.appendingPathComponent("economy.json")
        let json = """
        {"agents":{"Radion":{"bitMultiplierLevel":2,"spentBits":140}}}
        """
        try Data(json.utf8).write(to: economyURL)

        let reader = EconomyReader(url: economyURL)
        // Level 2 → 1.0 + 2*0.25 = 1.5
        XCTAssertEqual(reader.multiplier(for: "Radion"), 1.5, accuracy: 0.001)
    }

    func test_economy_reader_returns_1x_for_unknown_agent() throws {
        let economyURL = tempDir.appendingPathComponent("economy.json")
        let json = """
        {"agents":{"Radion":{"bitMultiplierLevel":1,"spentBits":50}}}
        """
        try Data(json.utf8).write(to: economyURL)

        let reader = EconomyReader(url: economyURL)
        XCTAssertEqual(reader.multiplier(for: "Other"), 1.0, accuracy: 0.001)
    }

    func test_economy_reader_returns_1x_when_file_missing() throws {
        let reader = EconomyReader(url: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(reader.multiplier(for: "Radion"), 1.0, accuracy: 0.001)
    }

    func test_economy_reader_returns_1x_for_nil_agent() throws {
        let reader = EconomyReader(url: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(reader.multiplier(for: nil), 1.0, accuracy: 0.001)
    }

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}
