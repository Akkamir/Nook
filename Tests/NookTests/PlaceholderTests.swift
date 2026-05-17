import XCTest
@testable import NookDaemon

final class PlaceholderTests: XCTestCase {
    func test_models_compile() {
        let state = LedgerState.empty
        XCTAssertEqual(state.totalBits, 0)
    }
}
