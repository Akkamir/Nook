import XCTest
@testable import Nook

final class CharIndexTests: XCTestCase {
    // The sprite index must be derived from a process-stable hash so an agent
    // keeps the same character across app launches. String.hashValue is seeded
    // per-process and would re-roll, so we pin the algorithm with golden values.
    func test_char_index_is_stable_golden_values() {
        XCTAssertEqual(NPCSprite.charIndex(for: "Radion", count: 6), 2)
        XCTAssertEqual(NPCSprite.charIndex(for: "Nook", count: 6), 0)
        XCTAssertEqual(NPCSprite.charIndex(for: "", count: 6), 1)
        XCTAssertEqual(NPCSprite.charIndex(for: "A", count: 6), 4)
    }

    func test_char_index_is_deterministic_for_same_id() {
        let first = NPCSprite.charIndex(for: "some-agent", count: 6)
        let second = NPCSprite.charIndex(for: "some-agent", count: 6)
        XCTAssertEqual(first, second)
    }

    func test_char_index_is_within_bounds() {
        for id in ["a", "bb", "ccc", "Radion", "déjà", "🦊"] {
            let index = NPCSprite.charIndex(for: id, count: 6)
            XCTAssertTrue((0..<6).contains(index), "index \(index) out of range for \(id)")
        }
    }
}
