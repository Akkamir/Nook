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
        XCTAssertEqual(state.sessions["s1"]?.totalTokens, 1_100)
        XCTAssertEqual(state.sessions["s1"]?.agentName, "Radion")
    }

    func test_decodes_activity_and_session_subject_fields() throws {
        let json = #"{"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,"activitySeq":2,"recentActivity":[{"agentName":"Radion","sessionId":"s1","kind":"file","payload":"Auth.swift","seq":2}],"sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion","startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":1,"outputTokens":1,"totalBits":0,"task":"refactor","filesTouched":["/p/Auth.swift"],"editCount":3}}}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LedgerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.activitySeq, 2)
        XCTAssertEqual(state.recentActivity.first?.kind, "file")
        XCTAssertEqual(state.sessions["s1"]?.task, "refactor")
        XCTAssertEqual(state.sessions["s1"]?.editCount, 3)
    }

    func test_agent_bond_recomputes_from_tokens_when_decoding_existing_ledger() throws {
        let json = """
        {"totalBits":0,"pendingBits":0,"agents":{"Radion":{"name":"Radion","totalTokens":4000000000,"bond":5,"totalBits":1}},
         "lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LedgerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.agents["Radion"]?.bond, 20)
    }

    func test_agent_zero_total_bits_decodes_as_zero() throws {
        let json = """
        {"totalBits":100,"pendingBits":0,"agents":{"Radion":{"name":"Radion","totalTokens":7000,"bond":1,"totalBits":0}},
         "lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LedgerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.agents["Radion"]?.totalBits, 0)
    }
}
