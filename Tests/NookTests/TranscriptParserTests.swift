import XCTest
@testable import NookDaemon

final class TranscriptParserTests: XCTestCase {

    func test_parse_assistant_line_with_usage() throws {
        let line = """
        {"type":"assistant","message":{"role":"assistant","content":[],"usage":{"input_tokens":4821,"output_tokens":312}}}
        """
        let result = TranscriptParser.parseLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.inputTokens, 4821)
        XCTAssertEqual(result?.outputTokens, 312)
    }

    func test_parse_user_line_returns_entry_with_zero_tokens() {
        // New contract: any message line parses. A user line carries no usage
        // (0 tokens) but does carry role/userText for subject capture.
        let line = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        """
        let result = TranscriptParser.parseLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.inputTokens, 0)
        XCTAssertEqual(result?.outputTokens, 0)
        XCTAssertEqual(result?.role, "user")
        XCTAssertEqual(result?.userText, "hello")
    }

    func test_parse_empty_line_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine(""))
    }

    func test_parse_malformed_json_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine("{not valid json}"))
    }

    func test_bits_calculation() throws {
        let line = """
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":1000,"output_tokens":1000}}}
        """
        let parsed = try XCTUnwrap(TranscriptParser.parseLine(line))
        let event = TokenEvent(sessionId: "t", projectPath: "", cwd: nil,
                               inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens,
                               cacheCreationTokens: parsed.cacheCreationTokens,
                               cacheReadTokens: parsed.cacheReadTokens,
                               timestamp: parsed.timestamp)
        // 1000 input * (1.0 * 5/1000) + 1000 output * (5.0 * 5/1000) = 5 + 25 = 30
        XCTAssertEqual(event.bits, 30.0, accuracy: 0.001)
    }

    func test_parses_and_weights_cache_tokens() throws {
        let line = """
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":1000,"output_tokens":0,"cache_creation_input_tokens":1000,"cache_read_input_tokens":10000}}}
        """
        let parsed = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(parsed.cacheCreationTokens, 1000)
        XCTAssertEqual(parsed.cacheReadTokens, 10000)
        let event = TokenEvent(sessionId: "t", projectPath: "", cwd: nil,
                               inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens,
                               cacheCreationTokens: parsed.cacheCreationTokens,
                               cacheReadTokens: parsed.cacheReadTokens,
                               timestamp: parsed.timestamp)
        // weighted tokens = 1000*1.0 + 0*5.0 + 1000*1.25 + 10000*0.0 = 2250
        // bits = 2250/1000 * 5 = 11.25 (cacheRead excluded — quadratic accumulation in subagent sessions)
        XCTAssertEqual(event.bits, 11.25, accuracy: 0.001)
    }

    func test_bond_tokens_match_sonnet_weights() throws {
        let line = """
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":1000,"output_tokens":1000,"cache_creation_input_tokens":1000,"cache_read_input_tokens":10000}}}
        """
        let parsed = try XCTUnwrap(TranscriptParser.parseLine(line))
        let event = TokenEvent(sessionId: "t", projectPath: "", cwd: nil,
                               inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens,
                               cacheCreationTokens: parsed.cacheCreationTokens,
                               cacheReadTokens: parsed.cacheReadTokens,
                               timestamp: parsed.timestamp)
        // weighted = 1000*1 + 1000*5 + 1000*1.25 + 10000*0.0 = 7250 (cacheRead excluded)
        XCTAssertEqual(event.bondTokens, 7_250)
    }

    func test_parse_line_without_cache_fields_defaults_to_zero() throws {
        let line = """
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":100,"output_tokens":200}}}
        """
        let parsed = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(parsed.cacheCreationTokens, 0)
        XCTAssertEqual(parsed.cacheReadTokens, 0)
    }

    func test_parses_tokens_real_timestamp_and_cwd() throws {
        let line = """
        {"cwd":"/Users/me/Code/Nook","timestamp":"2026-06-01T10:30:00Z","message":{"usage":{"input_tokens":120,"output_tokens":340}}}
        """
        let entry = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(entry.inputTokens, 120)
        XCTAssertEqual(entry.outputTokens, 340)
        XCTAssertEqual(entry.cwd, "/Users/me/Code/Nook")
        let expected = ISO8601DateFormatter().date(from: "2026-06-01T10:30:00Z")
        XCTAssertEqual(entry.timestamp, expected)
    }

    func test_missing_timestamp_falls_back_to_now() throws {
        let line = """
        {"message":{"usage":{"input_tokens":1,"output_tokens":1}}}
        """
        let before = Date()
        let entry = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertNil(entry.cwd)
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
    }

    func test_line_without_usage_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine("{}"))
    }

    func test_parses_user_task_text() throws {
        let line = #"{"cwd":"/c/Nook","gitBranch":"main","timestamp":"2026-06-01T10:00:00Z","message":{"role":"user","content":"refactor the auth module"}}"#
        let e = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(e.role, "user")
        XCTAssertEqual(e.userText, "refactor the auth module")
        XCTAssertEqual(e.gitBranch, "main")
        XCTAssertTrue(e.toolUses.isEmpty)
    }

    func test_user_tool_result_only_has_no_task_text() throws {
        let line = #"{"message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#
        let e = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(e.role, "user")
        XCTAssertNil(e.userText)
    }

    func test_parses_assistant_tool_uses() throws {
        let line = #"{"timestamp":"2026-06-01T10:05:00Z","message":{"role":"assistant","content":[{"type":"thinking","text":"hmm"},{"type":"tool_use","name":"Edit","input":{"file_path":"/c/Nook/Auth.swift"}},{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}],"usage":{"input_tokens":10,"output_tokens":20}}}"#
        let e = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(e.role, "assistant")
        XCTAssertEqual(e.inputTokens, 10)
        XCTAssertEqual(e.outputTokens, 20)
        XCTAssertEqual(e.toolUses.count, 2)
        XCTAssertEqual(e.toolUses[0].name, "Edit")
        XCTAssertEqual(e.toolUses[0].filePath, "/c/Nook/Auth.swift")
        XCTAssertEqual(e.toolUses[1].name, "Bash")
        XCTAssertEqual(e.toolUses[1].command, "swift test")
    }

    func test_non_message_line_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine(#"{"type":"summary","leafUuid":"x"}"#))
    }
}
