import XCTest
@testable import Nook

final class BitShowerTests: XCTestCase {
    func test_zero_gain_produces_no_pops() {
        XCTAssertTrue(NPCSprite.bitShowerChunks(0).isEmpty)
    }

    func test_small_gain_stays_whole() {
        XCTAssertEqual(NPCSprite.bitShowerChunks(3), [3])
        XCTAssertEqual(NPCSprite.bitShowerChunks(9), [9]) // below minChunk*2
    }

    func test_split_preserves_total() {
        for total in [10.0, 23.0, 54.0, 137.0, 512.0] {
            let chunks = NPCSprite.bitShowerChunks(total)
            XCTAssertEqual(chunks.reduce(0, +), total, accuracy: 0.0001)
        }
    }

    func test_chunks_never_weaker_than_min_when_split() {
        for total in [10.0, 23.0, 54.0, 137.0, 512.0] {
            let chunks = NPCSprite.bitShowerChunks(total, minChunk: 5)
            guard chunks.count > 1 else { continue }
            XCTAssertGreaterThanOrEqual(chunks.min() ?? 0, 5 - 0.0001)
        }
    }

    func test_pop_count_is_capped() {
        XCTAssertLessThanOrEqual(NPCSprite.bitShowerChunks(10_000).count, 6)
    }
}
