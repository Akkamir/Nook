import XCTest
@testable import NookDaemon

final class UpgradeTests: XCTestCase {
    private var tempDir: URL!
    private var ledger: Ledger!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ledger = Ledger(url: tempDir.appendingPathComponent("ledger.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_purchase_request_accepted_when_agent_has_available_bits() throws {
        var ledgerState = LedgerState.empty
        ledgerState.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 0, bond: 1, totalBits: 120)
        var upgrades = UpgradeState.empty
        let request = UpgradePurchaseRequest(agentName: "Radion", upgrade: .bitMultiplier, requestedAt: date("2026-06-07T10:00:00Z"))

        let result = UpgradeEconomy.apply(request: request, ledger: ledgerState, upgrades: &upgrades)

        XCTAssertEqual(result, .accepted)
        let agentUpgrades = try XCTUnwrap(upgrades.agents["Radion"])
        XCTAssertEqual(agentUpgrades.bitMultiplierLevel, 1)
        XCTAssertEqual(agentUpgrades.spentBits, 50, accuracy: 0.001)
        XCTAssertEqual(agentUpgrades.bitMultiplier, 1.25, accuracy: 0.001)
    }

    func test_purchase_rejected_when_agent_has_insufficient_available_bits() throws {
        var ledgerState = LedgerState.empty
        ledgerState.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 0, bond: 1, totalBits: 49)
        var upgrades = UpgradeState.empty
        let request = UpgradePurchaseRequest(agentName: "Radion", upgrade: .bitMultiplier, requestedAt: date("2026-06-07T10:00:00Z"))

        let result = UpgradeEconomy.apply(request: request, ledger: ledgerState, upgrades: &upgrades)

        XCTAssertEqual(result, .rejectedInsufficientBits)
        XCTAssertNil(upgrades.agents["Radion"])
    }

    func test_purchase_rejected_for_unknown_agent() throws {
        let ledgerState = LedgerState.empty
        var upgrades = UpgradeState.empty
        let request = UpgradePurchaseRequest(agentName: "Radion", upgrade: .bitMultiplier, requestedAt: date("2026-06-07T10:00:00Z"))

        let result = UpgradeEconomy.apply(request: request, ledger: ledgerState, upgrades: &upgrades)

        XCTAssertEqual(result, .rejectedUnknownAgent)
        XCTAssertTrue(upgrades.agents.isEmpty)
    }

    func test_spent_bits_reduce_available_without_mutating_cumulative_ledger() throws {
        var ledgerState = LedgerState.empty
        ledgerState.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 0, bond: 1, totalBits: 120)
        var upgrades = UpgradeState.empty

        _ = UpgradeEconomy.apply(
            request: UpgradePurchaseRequest(agentName: "Radion", upgrade: .bitMultiplier, requestedAt: date("2026-06-07T10:00:00Z")),
            ledger: ledgerState,
            upgrades: &upgrades
        )

        XCTAssertEqual(try XCTUnwrap(ledgerState.agents["Radion"]).totalBits, 120, accuracy: 0.001)
        XCTAssertEqual(UpgradeEconomy.availableBits(for: "Radion", ledger: ledgerState, upgrades: upgrades), 70, accuracy: 0.001)
    }

    func test_multiplier_applies_only_to_future_attributed_events_for_that_agent() throws {
        var state = LedgerState.empty
        state.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 0, bond: 1, totalBits: 120)
        var upgrades = UpgradeState.empty
        _ = UpgradeEconomy.apply(
            request: UpgradePurchaseRequest(agentName: "Radion", upgrade: .bitMultiplier, requestedAt: date("2026-06-07T10:00:00Z")),
            ledger: state,
            upgrades: &upgrades
        )

        let event = TokenEvent(
            sessionId: "s1",
            projectPath: "/p",
            cwd: "/p",
            inputTokens: 1000,
            outputTokens: 1000,
            timestamp: date("2026-06-07T10:05:00Z")
        )
        ledger.apply(event: event, agentName: "Radion", upgrades: upgrades, to: &state)
        ledger.apply(event: event, agentName: "Other", upgrades: upgrades, to: &state)
        ledger.apply(event: event, agentName: nil, upgrades: upgrades, to: &state)

        XCTAssertEqual(try XCTUnwrap(state.agents["Radion"]).totalBits, 145, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.agents["Other"]).totalBits, 20, accuracy: 0.001)
        XCTAssertEqual(state.totalBits, 65, accuracy: 0.001)
        XCTAssertEqual(state.recentEvents.map(\.bits), [25, 20, 20])
    }

    private func date(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }
}
