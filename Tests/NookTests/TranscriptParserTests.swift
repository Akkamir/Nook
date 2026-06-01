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

    func test_parse_line_without_usage_returns_nil() {
        let line = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        """
        let result = TranscriptParser.parseLine(line)
        XCTAssertNil(result)
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
        let event = TokenEvent(sessionId: "t", projectPath: "", cwd: nil, inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens, timestamp: parsed.timestamp)
        // 1000 input * 5/1000 + 1000 output * 15/1000 = 5 + 15 = 20
        XCTAssertEqual(event.bits, 20.0, accuracy: 0.001)
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
}
