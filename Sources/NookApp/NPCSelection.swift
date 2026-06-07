import Foundation

struct NPCSelection: Equatable {
    let id: String
    let name: String
    let bond: Int
    let totalTokens: Int
    let totalBits: Double
    let availableBits: Double
    let bitMultiplier: Double
    let activeSessionCount: Int
    let trait: NPCWorkTrait

    // History (Task 8)
    let projects: [ProjectRollup]
    let recentSessions: [SessionRecord]
    let sessionMemories: [String: GeneratedSessionMemory]
    let moments: [Moment]
    let currentStreakDays: Int
    let longestSessionSeconds: TimeInterval
}
