import XCTest
@testable import Nook

final class UpgradeStateAppTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_available_bits_subtracts_spent_from_cumulative_agent_bits() throws {
        let ledger = LedgerState(
            totalBitsRaw: 120, pendingBits: 0,
            agents: ["Radion": agent(name: "Radion", totalBits: 120)],
            lastUpdated: Date(), recentEvents: [], eventSeq: 0
        )
        let upgrades = UpgradeState(
            agents: ["Radion": AgentUpgradeState(bitMultiplierLevel: 1, spentBits: 50)]
        )

        XCTAssertEqual(UpgradeEconomy.availableBits(for: "Radion", ledger: ledger, upgrades: upgrades), 70, accuracy: 0.001)
        let multiplier = try XCTUnwrap(upgrades.agents["Radion"]?.bitMultiplier)
        XCTAssertEqual(multiplier, 1.25, accuracy: 0.001)
    }

    func test_economy_apply_accepted_and_deducts_bits() throws {
        let ledger = LedgerState(
            totalBitsRaw: 120, pendingBits: 0,
            agents: ["Radion": agent(name: "Radion", totalBits: 120)],
            lastUpdated: Date(), recentEvents: [], eventSeq: 0
        )
        var upgrades = UpgradeState.empty

        let accepted = UpgradeEconomy.apply(.bitMultiplier, for: "Radion", ledger: ledger, upgrades: &upgrades)

        XCTAssertTrue(accepted)
        let agentState = try XCTUnwrap(upgrades.agents["Radion"])
        XCTAssertEqual(agentState.bitMultiplierLevel, 1)
        XCTAssertEqual(agentState.spentBits, 50, accuracy: 0.001)
    }

    func test_economy_apply_rejected_when_insufficient_bits() throws {
        let ledger = LedgerState(
            totalBitsRaw: 49, pendingBits: 0,
            agents: ["Radion": agent(name: "Radion", totalBits: 49)],
            lastUpdated: Date(), recentEvents: [], eventSeq: 0
        )
        var upgrades = UpgradeState.empty

        let accepted = UpgradeEconomy.apply(.bitMultiplier, for: "Radion", ledger: ledger, upgrades: &upgrades)

        XCTAssertFalse(accepted)
        XCTAssertNil(upgrades.agents["Radion"])
    }

    func test_economy_store_round_trips() throws {
        let url = tempDir.appendingPathComponent("economy.json")
        let store = EconomyStore(url: url)
        let state = UpgradeState(
            agents: ["Radion": AgentUpgradeState(bitMultiplierLevel: 3, spentBits: 290)],
            lastUpdated: iso("2026-06-07T10:00:00Z")
        )

        try store.save(state)
        let loaded = store.load()

        XCTAssertEqual(loaded.agents["Radion"]?.bitMultiplierLevel, 3)
        let spentBits = try XCTUnwrap(loaded.agents["Radion"]?.spentBits)
        XCTAssertEqual(spentBits, 290, accuracy: 0.001)
        let loadedMultiplier = try XCTUnwrap(loaded.agents["Radion"]?.bitMultiplier)
        XCTAssertEqual(loadedMultiplier, 1.75, accuracy: 0.001)
    }

    func test_economy_store_load_returns_empty_when_file_missing() {
        let store = EconomyStore(url: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(store.load(), .empty)
    }

    private func agent(name: String, totalBits: Double) -> AgentRecord {
        let json = """
        {"name":"\(name)","totalTokens":0,"bond":1,"totalBits":\(totalBits)}
        """
        return try! JSONDecoder().decode(AgentRecord.self, from: Data(json.utf8))
    }

    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}
