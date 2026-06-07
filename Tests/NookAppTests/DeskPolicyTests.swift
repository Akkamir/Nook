import XCTest
@testable import Nook

final class DeskPolicyTests: XCTestCase {
    // A working NPC only walks to a fixed desk tile once it has earned a desk.
    // Below the bond threshold it works near where it currently stands.
    func test_low_bond_has_no_desk() {
        XCTAssertFalse(DeskPolicy.hasDesk(bond: 1))
        XCTAssertFalse(DeskPolicy.hasDesk(bond: 2))
    }

    func test_bond_at_or_above_threshold_has_desk() {
        XCTAssertEqual(DeskPolicy.bondThreshold, 3)
        XCTAssertTrue(DeskPolicy.hasDesk(bond: 3))
        XCTAssertTrue(DeskPolicy.hasDesk(bond: 4))
        XCTAssertTrue(DeskPolicy.hasDesk(bond: 5))
    }

    func test_eligibility_changes_only_when_crossing_threshold() {
        XCTAssertFalse(DeskPolicy.eligibilityChanged(from: 1, to: 2))
        XCTAssertTrue(DeskPolicy.eligibilityChanged(from: 2, to: 3))
        XCTAssertFalse(DeskPolicy.eligibilityChanged(from: 3, to: 4))
        XCTAssertTrue(DeskPolicy.eligibilityChanged(from: 3, to: 2))
    }
}
