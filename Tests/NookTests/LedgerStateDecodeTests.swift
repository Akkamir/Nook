import XCTest
@testable import NookDaemon

final class LedgerStateDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> LedgerState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LedgerState.self, from: Data(json.utf8))
    }

    func test_legacy_ledger_without_sessions_decodes_to_empty_sessions() throws {
        let json = """
        {"totalBits":10,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0}
        """
        let state = try decode(json)
        XCTAssertTrue(state.sessions.isEmpty)
    }

    func test_ledger_with_sessions_decodes_them() throws {
        let json = """
        {"totalBits":10,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,
         "sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion",
         "startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":100,"outputTokens":200,"totalBits":3.5}}}
        """
        let state = try decode(json)
        XCTAssertEqual(state.sessions["s1"]?.project, "Nook")
        XCTAssertEqual(state.sessions["s1"]?.totalTokens, 300)
    }

    func test_legacy_session_without_subject_fields_decodes_with_defaults() throws {
        let json = #"{"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,"sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion","startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":100,"outputTokens":200,"totalBits":3.5}}}"#
        let state = try decode(json)
        let s = try XCTUnwrap(state.sessions["s1"])
        XCTAssertNil(s.task)
        XCTAssertEqual(s.filesTouched, [])
        XCTAssertEqual(s.editCount, 0)
        XCTAssertEqual(s.firedKinds, [])
        XCTAssertTrue(state.recentActivity.isEmpty)
        XCTAssertEqual(state.activitySeq, 0)
    }
}
