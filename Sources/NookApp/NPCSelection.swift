import Foundation

struct NPCSelection: Equatable {
    let id: String
    let name: String
    let bond: Int
    let totalTokens: Int
    let totalBits: Double
    let activeSessionCount: Int
    let trait: NPCWorkTrait
}
