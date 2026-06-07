import Foundation

struct BondProgress: Equatable {
    let currentBond: Int
    let nextBond: Int?
    let currentThreshold: Int
    let nextThreshold: Int?
    let fraction: Double
    let label: String

    var isMaxBond: Bool {
        nextBond == nil
    }

    static func forTokens(_ tokens: Int) -> BondProgress {
        let clampedTokens = max(tokens, 0)
        let thresholds = BondScale.thresholds

        let currentIndex = thresholds.lastIndex { clampedTokens >= $0.tokens } ?? 0
        let current = thresholds[currentIndex]

        guard currentIndex + 1 < thresholds.count else {
            return BondProgress(
                currentBond: current.level,
                nextBond: nil,
                currentThreshold: current.tokens,
                nextThreshold: nil,
                fraction: 1,
                label: "Max bond"
            )
        }

        let next = thresholds[currentIndex + 1]
        let span = max(next.tokens - current.tokens, 1)
        let rawFraction = Double(clampedTokens - current.tokens) / Double(span)
        let fraction = min(max(rawFraction, 0), 1)

        return BondProgress(
            currentBond: current.level,
            nextBond: next.level,
            currentThreshold: current.tokens,
            nextThreshold: next.tokens,
            fraction: fraction,
            label: "\(Self.format(clampedTokens)) / \(Self.format(next.tokens)) tokens"
        )
    }

    private static func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
