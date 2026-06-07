import XCTest
@testable import Nook

final class DeskLayoutTests: XCTestCase {
    func test_front_desk_top_sits_at_bust_height() {
        let layout = DeskLayout.front(
            tileSize: 16,
            displayScale: 2,
            characterHeight: 64,
            deskPixelSize: CGSize(width: 48, height: 32),
            pcPixelSize: CGSize(width: 16, height: 32)
        )

        XCTAssertEqual(layout.deskNodeYOffset, -46)
        XCTAssertEqual(layout.deskTopY, 18)
        XCTAssertLessThan(layout.deskTopY, 24)
        XCTAssertGreaterThan(layout.deskTopY, 12)
    }

    func test_pc_sits_on_surface_without_covering_face() {
        let layout = DeskLayout.front(
            tileSize: 16,
            displayScale: 2,
            characterHeight: 64,
            deskPixelSize: CGSize(width: 48, height: 32),
            pcPixelSize: CGSize(width: 16, height: 32)
        )

        XCTAssertEqual(layout.pcPosition.x, 0)
        XCTAssertEqual(layout.pcPosition.y, 40)
        XCTAssertGreaterThan(layout.pcTopY, 20)
        XCTAssertLessThan(layout.pcTopY, 34)
    }
}
