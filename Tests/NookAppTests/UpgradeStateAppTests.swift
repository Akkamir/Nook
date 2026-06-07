import XCTest
@testable import Nook

final class UpgradeStateAppTests: XCTestCase {
    func test_available_bits_subtracts_spent_from_cumulative_agent_bits() {
        let ledger = LedgerState(
            totalBits: 120,
            pendingBits: 0,
            agents: ["Radion": agent(name: "Radion", totalBits: 120)],
            lastUpdated: Date(),
            recentEvents: [],
            eventSeq: 0
        )
        let upgrades = UpgradeState(
            agents: ["Radion": AgentUpgradeState(bitMultiplierLevel: 1, spentBits: 50)],
            processedRequestCount: 1,
            lastUpdated: Date()
        )

        XCTAssertEqual(UpgradeEconomy.availableBits(for: "Radion", ledger: ledger, upgrades: upgrades), 70, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(upgrades.agents["Radion"]).bitMultiplier, 1.25, accuracy: 0.001)
    }

    func test_purchase_request_round_trips_as_json_line() throws {
        let request = UpgradePurchaseRequest(agentName: "Radion", upgrade: .bitMultiplier, requestedAt: iso("2026-06-07T10:00:00Z"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UpgradePurchaseRequest.self, from: data)

        XCTAssertEqual(decoded.agentName, "Radion")
        XCTAssertEqual(decoded.upgrade, .bitMultiplier)
        XCTAssertEqual(decoded.requestedAt, request.requestedAt)
    }

    private func agent(name: String, totalBits: Double) -> AgentRecord {
        let json = """
        {"name":"\(name)","totalTokens":0,"bond":1,"totalBits":\(totalBits)}
        """
        return try! JSONDecoder().decode(AgentRecord.self, from: Data(json.utf8))
    }

    private func iso(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }
}
