import Foundation

enum BondScale {
    // Scaled ×40 from the pre-cache baseline so progression stays similar once
    // bond tokens include weighted cache read/write (dominant in real sessions).
    static let thresholds: [(level: Int, tokens: Int)] = [
        (1, 0),
        (2, 400_000),
        (3, 667_240),
        (4, 1_113_040),
        (5, 1_856_640),
        (6, 3_097_040),
        (7, 5_166_200),
        (8, 8_617_720),
        (9, 14_375_240),
        (10, 23_979_360),
        (11, 40_000_000),
        (12, 66_724_000),
        (13, 111_302_360),
        (14, 185_663_560),
        (15, 309_705_480),
        (16, 516_619_880),
        (17, 861_773_880),
        (18, 1_437_525_480),
        (19, 2_397_937_000),
        (20, 4_000_000_000)
    ]

    static func level(for tokens: Int) -> Int {
        let clampedTokens = max(tokens, 0)
        return thresholds.last { clampedTokens >= $0.tokens }?.level ?? 1
    }
}
