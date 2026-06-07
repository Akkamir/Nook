import Foundation

enum BondScale {
    static let thresholds: [(level: Int, tokens: Int)] = [
        (1, 0),
        (2, 10_000),
        (3, 16_681),
        (4, 27_826),
        (5, 46_416),
        (6, 77_426),
        (7, 129_155),
        (8, 215_443),
        (9, 359_381),
        (10, 599_484),
        (11, 1_000_000),
        (12, 1_668_100),
        (13, 2_782_559),
        (14, 4_641_589),
        (15, 7_742_637),
        (16, 12_915_497),
        (17, 21_544_347),
        (18, 35_938_137),
        (19, 59_948_425),
        (20, 100_000_000)
    ]

    static func level(for tokens: Int) -> Int {
        let clampedTokens = max(tokens, 0)
        return thresholds.last { clampedTokens >= $0.tokens }?.level ?? 1
    }
}
