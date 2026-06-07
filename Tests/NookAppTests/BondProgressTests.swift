import XCTest
@testable import Nook

final class BondProgressTests: XCTestCase {
    func test_progress_below_first_threshold_targets_bond_two() {
        let progress = BondProgress.forTokens(200_000)

        XCTAssertEqual(progress.currentBond, 1)
        XCTAssertEqual(progress.nextBond, 2)
        XCTAssertEqual(progress.currentThreshold, 0)
        XCTAssertEqual(progress.nextThreshold, 400_000)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.label, "200,000 / 400,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_between_middle_thresholds_targets_next_bond() {
        let progress = BondProgress.forTokens(2_000_000)

        XCTAssertEqual(progress.currentBond, 5)
        XCTAssertEqual(progress.nextBond, 6)
        XCTAssertEqual(progress.currentThreshold, 1_856_640)
        XCTAssertEqual(progress.nextThreshold, 3_097_040)
        XCTAssertEqual(progress.fraction, 143_360.0 / 1_240_400.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "2,000,000 / 3,097,040 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_before_new_max_bond_targets_next_level() {
        let progress = BondProgress.forTokens(50_000_000)

        XCTAssertEqual(progress.currentBond, 11)
        XCTAssertEqual(progress.nextBond, 12)
        XCTAssertEqual(progress.currentThreshold, 40_000_000)
        XCTAssertEqual(progress.nextThreshold, 66_724_000)
        XCTAssertEqual(progress.label, "50,000,000 / 66,724,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_at_new_max_bond_is_complete() {
        let progress = BondProgress.forTokens(4_000_000_000)

        XCTAssertEqual(progress.currentBond, 20)
        XCTAssertNil(progress.nextBond)
        XCTAssertEqual(progress.currentThreshold, 4_000_000_000)
        XCTAssertNil(progress.nextThreshold)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "Max bond")
        XCTAssertTrue(progress.isMaxBond)
    }
}
