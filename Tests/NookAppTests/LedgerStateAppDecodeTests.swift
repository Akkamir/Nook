import XCTest
@testable import Nook

final class LedgerStateAppDecodeTests: XCTestCase {
    func test_decodes_sessions_and_defaults_when_absent() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let legacy = """
        {"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0}
        """
        XCTAssertTrue(try decoder.decode(LedgerState.self, from: Data(legacy.utf8)).sessions.isEmpty)

        let withSessions = """
        {"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,
         "sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion",
         "startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":100,"outputTokens":200,"totalBits":3.5}}}
        """
        let state = try decoder.decode(LedgerState.self, from: Data(withSessions.utf8))
        XCTAssertEqual(state.sessions["s1"]?.totalTokens, 300)
        XCTAssertEqual(state.sessions["s1"]?.agentName, "Radion")
    }
}
