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

    func test_apply_stores_raw_bits_without_multiplier() throws {
        var state = LedgerState.empty

        let event = TokenEvent(
            sessionId: "s1", projectPath: "/p", cwd: "/p",
            inputTokens: 1000, outputTokens: 1000,
            timestamp: date("2026-06-07T10:05:00Z")
        )

        ledger.apply(event: event, agentName: "Radion", to: &state)

        XCTAssertEqual(try XCTUnwrap(state.agents["Radion"]).totalBitsRaw, 30, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.recentEvents.last).rawBits, 30, accuracy: 0.001)
        XCTAssertEqual(state.totalBitsRaw, 30, accuracy: 0.001)
    }

    func test_unattributed_event_credits_global_raw_bits_only() throws {
        var state = LedgerState.empty

        let event = TokenEvent(
            sessionId: "s2", projectPath: "/p", cwd: "/p",
            inputTokens: 1000, outputTokens: 0,
            timestamp: date("2026-06-07T10:05:00Z")
        )

        ledger.apply(event: event, agentName: nil, to: &state)

        XCTAssertTrue(state.agents.isEmpty)
        XCTAssertEqual(state.totalBitsRaw, 5, accuracy: 0.001)
        XCTAssertEqual(state.globalBitsRaw, 5, accuracy: 0.001)
        let eventRecord = try XCTUnwrap(state.recentEvents.last)
        XCTAssertNil(eventRecord.agentName)
        XCTAssertEqual(eventRecord.rawBits, 5, accuracy: 0.001)
    }

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}
