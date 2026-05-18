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
        let result = try XCTUnwrap(TranscriptParser.parseLine(line))
        // 1000 input * 5/1000 + 1000 output * 15/1000 = 5 + 15 = 20
        XCTAssertEqual(result.bits, 20.0, accuracy: 0.001)
    }
}
