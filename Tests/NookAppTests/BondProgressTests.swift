import XCTest
@testable import Nook

final class BondProgressTests: XCTestCase {
    func test_progress_below_first_threshold_targets_bond_two() {
        let progress = BondProgress.forTokens(100_000)

        XCTAssertEqual(progress.currentBond, 1)
        XCTAssertEqual(progress.nextBond, 2)
        XCTAssertEqual(progress.currentThreshold, 0)
        XCTAssertEqual(progress.nextThreshold, 200_000)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.label, "100,000 / 200,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_between_middle_thresholds_targets_next_bond() {
        let progress = BondProgress.forTokens(2_000_000)

        XCTAssertEqual(progress.currentBond, 6)
        XCTAssertEqual(progress.nextBond, 7)
        XCTAssertEqual(progress.currentThreshold, 1_548_520)
        XCTAssertEqual(progress.nextThreshold, 2_583_100)
        XCTAssertEqual(progress.fraction, 451_480.0 / 1_034_580.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "2,000,000 / 2,583,100 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_before_new_max_bond_targets_next_level() {
        let progress = BondProgress.forTokens(50_000_000)

        XCTAssertEqual(progress.currentBond, 12)
        XCTAssertEqual(progress.nextBond, 13)
        XCTAssertEqual(progress.currentThreshold, 33_362_000)
        XCTAssertEqual(progress.nextThreshold, 55_651_180)
        XCTAssertEqual(progress.label, "50,000,000 / 55,651,180 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_at_new_max_bond_is_complete() {
        let progress = BondProgress.forTokens(2_000_000_000)

        XCTAssertEqual(progress.currentBond, 20)
        XCTAssertNil(progress.nextBond)
        XCTAssertEqual(progress.currentThreshold, 2_000_000_000)
        XCTAssertNil(progress.nextThreshold)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "Max bond")
        XCTAssertTrue(progress.isMaxBond)
    }
}
