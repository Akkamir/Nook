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

        XCTAssertEqual(progress.currentBond, 5)
        XCTAssertEqual(progress.nextBond, 6)
        XCTAssertEqual(progress.currentThreshold, 46_416)
        XCTAssertEqual(progress.nextThreshold, 77_426)
        XCTAssertEqual(progress.fraction, 28_584.0 / 31_010.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "75,000 / 77,426 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_before_new_max_bond_targets_next_level() {
        let progress = BondProgress.forTokens(1_250_000)

        XCTAssertEqual(progress.currentBond, 11)
        XCTAssertEqual(progress.nextBond, 12)
        XCTAssertEqual(progress.currentThreshold, 1_000_000)
        XCTAssertEqual(progress.nextThreshold, 1_668_100)
        XCTAssertEqual(progress.label, "1,250,000 / 1,668,100 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_at_new_max_bond_is_complete() {
        let progress = BondProgress.forTokens(100_000_000)

        XCTAssertEqual(progress.currentBond, 20)
        XCTAssertNil(progress.nextBond)
        XCTAssertEqual(progress.currentThreshold, 100_000_000)
        XCTAssertNil(progress.nextThreshold)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "Max bond")
        XCTAssertTrue(progress.isMaxBond)
    }
}
