import Foundation

enum BondScale {
    // Scaled ×20 from the pre-cache baseline. Cache reads (previously ×0.1) were
    // excluded from bond tokens — they represented ~50% of old totals in subagent
    // sessions due to quadratic context re-reads. Halving the multiplier compensates
    // so per-session progression stays similar (~1–3 sessions per mid-game level).
    static let thresholds: [(level: Int, tokens: Int)] = [
        (1, 0),
        (2, 200_000),
        (3, 333_620),
        (4, 556_520),
        (5, 928_320),
        (6, 1_548_520),
        (7, 2_583_100),
        (8, 4_308_860),
        (9, 7_187_620),
        (10, 11_989_680),
        (11, 20_000_000),
        (12, 33_362_000),
        (13, 55_651_180),
        (14, 92_831_780),
        (15, 154_852_740),
        (16, 258_309_940),
        (17, 430_886_940),
        (18, 718_762_740),
        (19, 1_198_968_500),
        (20, 2_000_000_000)
    ]

    static func level(for tokens: Int) -> Int {
        let clampedTokens = max(tokens, 0)
        return thresholds.last { clampedTokens >= $0.tokens }?.level ?? 1
    }
}
