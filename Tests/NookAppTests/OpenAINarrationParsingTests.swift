import XCTest
@testable import Nook

final class OpenAINarrationParsingTests: XCTestCase {
    func test_stripCodeFence_unwraps_json_language_fence() {
        let fenced = "```json\n{\"title\":\"A\"}\n```"
        XCTAssertEqual(OpenAINarrationClient.stripCodeFence(fenced), "{\"title\":\"A\"}")
    }

    func test_stripCodeFence_unwraps_bare_fence() {
        let fenced = "```\n{\"a\":1}\n```"
        XCTAssertEqual(OpenAINarrationClient.stripCodeFence(fenced), "{\"a\":1}")
    }

    func test_stripCodeFence_passes_through_raw_json() {
        let raw = "{\"title\":\"B\"}"
        XCTAssertEqual(OpenAINarrationClient.stripCodeFence(raw), raw)
    }

    func test_stripCodeFence_trims_surrounding_whitespace() {
        let fenced = "  ```json\n  {\"k\":true}\n  ```  "
        XCTAssertEqual(OpenAINarrationClient.stripCodeFence(fenced), "{\"k\":true}")
    }

    func test_sanitizeSpokenLine_collapses_newlines_and_trims() {
        let raw = "  We're getting\nsomewhere.  "
        XCTAssertEqual(OpenAINarrationClient.sanitizeSpokenLine(raw), "We're getting somewhere.")
    }

    func test_sanitizeSpokenLine_keeps_short_line_unchanged() {
        let raw = "On commit ?"
        XCTAssertEqual(OpenAINarrationClient.sanitizeSpokenLine(raw), "On commit ?")
    }

    func test_sanitizeSpokenLine_truncates_on_word_boundary() {
        let raw = String(repeating: "word ", count: 40) // 200 chars
        let out = OpenAINarrationClient.sanitizeSpokenLine(raw, maxLength: 20)
        XCTAssertTrue(out.hasSuffix("…"))
        XCTAssertLessThanOrEqual(out.count, 21)
        XCTAssertFalse(out.contains("  "))
    }

    func test_reactionStyle_all_cases_have_nonempty_tone() {
        for style in ReactionStyle.allCases {
            XCTAssertFalse(style.tone.isEmpty, "ReactionStyle.\(style) has empty tone")
        }
    }

    func test_reactionStyle_all_tones_are_distinct() {
        let tones = ReactionStyle.allCases.map { $0.tone }
        XCTAssertEqual(tones.count, Set(tones).count, "Two ReactionStyle cases share the same tone fragment")
    }

    func test_reactionStyle_random_returns_valid_case() {
        let style = ReactionStyle.random()
        XCTAssertTrue(ReactionStyle.allCases.contains(style))
    }

    func test_reactionStyle_covers_ten_cases() {
        XCTAssertEqual(ReactionStyle.allCases.count, 10)
    }
}
