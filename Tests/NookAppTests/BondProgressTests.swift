import XCTest
@testable import Nook

final class BondProgressTests: XCTestCase {
    func test_progress_below_first_threshold_targets_bond_two() {
        let progress = BondProgress.forTokens(5_000)

        XCTAssertEqual(progress.currentBond, 1)
        XCTAssertEqual(progress.nextBond, 2)
        XCTAssertEqual(progress.currentThreshold, 0)
        XCTAssertEqual(progress.nextThreshold, 10_000)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.label, "5,000 / 10,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_between_middle_thresholds_targets_next_bond() {
        let progress = BondProgress.forTokens(75_000)

        XCTAssertEqual(progress.currentBond, 3)
        XCTAssertEqual(progress.nextBond, 4)
        XCTAssertEqual(progress.currentThreshold, 50_000)
        XCTAssertEqual(progress.nextThreshold, 200_000)
        XCTAssertEqual(progress.fraction, 25_000.0 / 150_000.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "75,000 / 200,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_at_max_bond_is_complete() {
        let progress = BondProgress.forTokens(1_250_000)

        XCTAssertEqual(progress.currentBond, 5)
        XCTAssertNil(progress.nextBond)
        XCTAssertEqual(progress.currentThreshold, 1_000_000)
        XCTAssertNil(progress.nextThreshold)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "Max bond")
        XCTAssertTrue(progress.isMaxBond)
    }
}
