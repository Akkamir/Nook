import Foundation

/// Decides whether an NPC has earned a fixed desk. Without a desk an NPC works
/// near where it currently stands instead of marching to a deterministic tile.
enum DeskPolicy {
    static let bondThreshold = 3

    static func hasDesk(bond: Int) -> Bool {
        bond >= bondThreshold
    }

    static func eligibilityChanged(from oldBond: Int, to newBond: Int) -> Bool {
        hasDesk(bond: oldBond) != hasDesk(bond: newBond)
    }
}
