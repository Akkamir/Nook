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

    func test_process_delta_credits_agent_wallet_and_village_bonus() throws {
        let ledger = ledgerState(agentBits: 100, bond: 1, globalBits: 0)
        var economy = EconomyState.empty

        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)

        let agent = try XCTUnwrap(economy.agents["Radion"])
        XCTAssertEqual(agent.wallet, 100, accuracy: 0.001)
        XCTAssertEqual(agent.lastProcessedRawBits, 100, accuracy: 0.001)
        XCTAssertEqual(economy.villageWallet, 10, accuracy: 0.001)
    }

    func test_process_delta_uses_additive_multiplier_and_village_gets_ten_percent_of_effective_gain() throws {
        let ledger = ledgerState(agentBits: 100, bond: 6, globalBits: 0)
        var economy = EconomyState.empty
        economy.agents["Radion"] = AgentEconomyState(bitMultiplierLevel: 2, bondDividendLevel: 2)

        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)

        // Bit multiplier L2 = +20%; Bond dividend L2 at bond 6 = +36%; total = 1.56x.
        let radion2 = try XCTUnwrap(economy.agents["Radion"])
        XCTAssertEqual(radion2.wallet, 156, accuracy: 0.001)
        XCTAssertEqual(economy.villageWallet, 15.6, accuracy: 0.001)
    }

    func test_global_delta_credits_village_only() throws {
        let ledger = ledgerState(agentBits: 0, bond: 1, globalBits: 80)
        var economy = EconomyState.empty

        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)

        XCTAssertNil(economy.agents["Radion"])
        XCTAssertEqual(economy.villageWallet, 80, accuracy: 0.001)
        XCTAssertEqual(economy.lastProcessedGlobalRawBits, 80, accuracy: 0.001)
    }

    func test_second_processing_without_delta_does_not_double_credit() throws {
        let ledger = ledgerState(agentBits: 100, bond: 1, globalBits: 20)
        var economy = EconomyState.empty

        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)
        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)

        let radion3 = try XCTUnwrap(economy.agents["Radion"])
        XCTAssertEqual(radion3.wallet, 100, accuracy: 0.001)
        XCTAssertEqual(economy.villageWallet, 30, accuracy: 0.001)
    }

    func test_negative_delta_resynchronizes_without_debiting_wallet() throws {
        let ledger = ledgerState(agentBits: 50, bond: 1, globalBits: 0)
        var economy = EconomyState.empty
        economy.agents["Radion"] = AgentEconomyState(wallet: 200, lastProcessedRawBits: 100)

        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)

        let radion4 = try XCTUnwrap(economy.agents["Radion"])
        XCTAssertEqual(radion4.wallet, 200, accuracy: 0.001)
        XCTAssertEqual(radion4.lastProcessedRawBits, 50, accuracy: 0.001)
    }

    func test_purchase_rules_respect_costs_and_bond_gates() throws {
        let ledger = ledgerState(agentBits: 10_000, bond: 6, globalBits: 0)
        var economy = EconomyState.empty
        economy.agents["Radion"] = AgentEconomyState(wallet: 10_000)

        XCTAssertTrue(EconomyEngine.apply(.bitMultiplier, for: "Radion", ledger: ledger, economy: &economy))
        let radion5 = try XCTUnwrap(economy.agents["Radion"])
        XCTAssertEqual(radion5.bitMultiplierLevel, 1)
        XCTAssertEqual(radion5.spentBits, 500, accuracy: 0.001)

        XCTAssertTrue(EconomyEngine.apply(.bondDividend, for: "Radion", ledger: ledger, economy: &economy))
        XCTAssertEqual(economy.agents["Radion"]?.bondDividendLevel, 1)

        XCTAssertTrue(EconomyEngine.apply(.trickle, for: "Radion", ledger: ledger, economy: &economy))
        XCTAssertEqual(economy.agents["Radion"]?.trickleCount, 1)
    }

    func test_bond_gates_reject_unavailable_upgrades() throws {
        let ledger = ledgerState(agentBits: 10_000, bond: 1, globalBits: 0)
        var economy = EconomyState.empty
        economy.agents["Radion"] = AgentEconomyState(wallet: 10_000, trickleCount: 2)

        XCTAssertFalse(EconomyEngine.apply(.bondDividend, for: "Radion", ledger: ledger, economy: &economy))
        XCTAssertFalse(EconomyEngine.apply(.trickle, for: "Radion", ledger: ledger, economy: &economy))
    }

    func test_migration_conservatively_seeds_wallets_and_checkpoints() throws {
        let ledger = ledgerState(agentBits: 20_000, bond: 6, globalBits: 300)
        var old = EconomyState.empty
        old.schemaVersion = 0
        old.agents["Radion"] = AgentEconomyState(
            spentBits: 9_999,
            bitMultiplierLevel: 99,
            bondDividendLevel: 99,
            trickleCount: 99
        )

        let migrated = EconomyEngine.migratedState(from: old, ledger: ledger)

        let agent = try XCTUnwrap(migrated.agents["Radion"])
        XCTAssertEqual(agent.wallet, 5_000, accuracy: 0.001) // Bond 6 cap.
        XCTAssertEqual(agent.spentBits, 0, accuracy: 0.001)
        XCTAssertEqual(agent.lastProcessedRawBits, 20_000, accuracy: 0.001)
        XCTAssertEqual(agent.bitMultiplierLevel, 6)
        XCTAssertEqual(agent.bondDividendLevel, 2)
        XCTAssertEqual(agent.trickleCount, 10)
        XCTAssertEqual(migrated.lastProcessedGlobalRawBits, 300, accuracy: 0.001)
        XCTAssertEqual(migrated.schemaVersion, EconomyEngine.currentSchemaVersion)
    }

    func test_economy_store_round_trips_new_state() throws {
        let url = tempDir.appendingPathComponent("economy.json")
        let store = EconomyStore(url: url)
        let state = EconomyState(
            schemaVersion: EconomyEngine.currentSchemaVersion,
            agents: ["Radion": AgentEconomyState(wallet: 123, trickleCount: 2)],
            villageWallet: 45,
            spentVillageBits: 5,
            lastProcessedGlobalRawBits: 10,
            lastUpdated: iso("2026-06-08T10:00:00Z"),
            migration: EconomyMigrationState()
        )

        try store.save(state)
        let loaded = store.load()

        let loadedRadion = try XCTUnwrap(loaded.agents["Radion"])
        XCTAssertEqual(loadedRadion.wallet, 123, accuracy: 0.001)
        XCTAssertEqual(loadedRadion.trickleCount, 2)
        XCTAssertEqual(loaded.villageWallet, 45, accuracy: 0.001)
        XCTAssertEqual(loaded.spentVillageBits, 5, accuracy: 0.001)
    }

    func test_economy_store_load_returns_empty_when_file_missing() {
        let store = EconomyStore(url: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(store.load(), .empty)
    }

    func test_cumulative_delta_credits_even_when_recent_events_are_empty() throws {
        var economy = EconomyState.empty
        var ledger = ledgerState(agentBits: 100, bond: 1, globalBits: 0)
        ledger = LedgerState(
            totalBitsRaw: ledger.totalBitsRaw,
            pendingBits: ledger.pendingBits,
            globalBitsRaw: ledger.globalBitsRaw,
            agents: ledger.agents,
            lastUpdated: ledger.lastUpdated,
            recentEvents: [],
            eventSeq: 42
        )

        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &economy)

        let agent = try XCTUnwrap(economy.agents["Radion"])
        XCTAssertEqual(agent.wallet, 100, accuracy: 0.001)
        XCTAssertEqual(economy.villageWallet, 10, accuracy: 0.001)
    }

    private func ledgerState(agentBits: Double, bond: Int, globalBits: Double) -> LedgerState {
        let agent = agentBits > 0
            ? ["Radion": agentRecord(name: "Radion", totalTokens: BondScale.thresholds.first { $0.level == bond }?.tokens ?? 0, totalBitsRaw: agentBits)]
            : [:]
        return LedgerState(
            totalBitsRaw: agentBits + globalBits,
            pendingBits: 0,
            globalBitsRaw: globalBits,
            agents: agent,
            lastUpdated: Date(),
            recentEvents: [],
            eventSeq: 0
        )
    }

    private func agentRecord(name: String, totalTokens: Int, totalBitsRaw: Double) -> AgentRecord {
        let json = """
        {"name":"\(name)","totalTokens":\(totalTokens),"bond":1,"totalBits":\(totalBitsRaw)}
        """
        return try! JSONDecoder().decode(AgentRecord.self, from: Data(json.utf8))
    }

    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}
