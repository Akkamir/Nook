import XCTest
@testable import Nook

final class VillageMapDataTests: XCTestCase {

    private func decodeMap(_ json: String) -> TiledMap {
        try! JSONDecoder().decode(TiledMap.self, from: json.data(using: .utf8)!)
    }

    private func makeMap(
        width: Int = 4,
        height: Int = 4,
        backgroundcolor: String? = nil,
        propLayerName: String = "Props (large: nature)",
        propData: [Int]? = nil
    ) -> TiledMap {
        let bgField = backgroundcolor.map { "\"backgroundcolor\":\"\($0)\"," } ?? ""
        var layersJSON = "[]"
        if let data = propData {
            let dataStr = data.map(String.init).joined(separator: ",")
            layersJSON = "[{\"id\":1,\"name\":\"\(propLayerName)\",\"type\":\"tilelayer\",\"data\":[\(dataStr)],\"width\":\(width),\"height\":\(height),\"visible\":true,\"opacity\":1.0}]"
        }
        let json = "{\"width\":\(width),\"height\":\(height),\"tilewidth\":32,\"tileheight\":32,\(bgField)\"layers\":\(layersJSON),\"tilesets\":[]}"
        return decodeMap(json)
    }

    func test_mapSize_is_tiles_times_displayTileSize() {
        let map = makeMap(width: 24, height: 24)
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        XCTAssertEqual(data.mapSize, CGSize(width: 768, height: 768))
    }

    func test_tileColumns_and_tileRows_match_map() {
        let map = makeMap(width: 10, height: 8)
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        XCTAssertEqual(data.tileColumns, 10)
        XCTAssertEqual(data.tileRows, 8)
    }

    func test_blockedTiles_empty_when_no_prop_layers() {
        let map = makeMap()
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        XCTAssertTrue(data.blockedTiles.isEmpty)
    }

    func test_blockedTiles_populated_from_large_nature_layer() {
        let map = makeMap(width: 3, height: 1,
                          propLayerName: "Props (large: nature)",
                          propData: [0, 5, 0])
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        XCTAssertEqual(data.blockedTiles, [TilePosition(tileX: 1, tileY: 0)])
    }

    func test_blockedTiles_populated_from_small_items_layer() {
        let map = makeMap(width: 3, height: 1,
                          propLayerName: "Props (small: items)",
                          propData: [3, 0, 0])
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        XCTAssertEqual(data.blockedTiles, [TilePosition(tileX: 0, tileY: 0)])
    }

    func test_blockedTiles_row_y_is_flipped_from_tiled() {
        let map = makeMap(width: 2, height: 2,
                          propLayerName: "Props (large: nature)",
                          propData: [7, 0, 0, 0])
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        XCTAssertEqual(data.blockedTiles, [TilePosition(tileX: 0, tileY: 1)])
    }

    func test_backdropColor_fallback_when_no_backgroundcolor() {
        let map = makeMap()
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        var r: CGFloat = -1
        data.backdropColor.getRed(&r, green: nil, blue: nil, alpha: nil)
        XCTAssertGreaterThanOrEqual(r, 0)
    }

    func test_backdropColor_parsed_from_hex_string() {
        let map = makeMap(backgroundcolor: "#ff8040")
        let data = VillageMapData.build(from: map, displayTileSize: 32)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        data.backdropColor.usingColorSpace(.deviceRGB)!
            .getRed(&r, green: &g, blue: &b, alpha: nil)
        XCTAssertEqual(r, CGFloat(0xFF) / 255, accuracy: 0.005)
        XCTAssertEqual(g, CGFloat(0x80) / 255, accuracy: 0.005)
        XCTAssertEqual(b, CGFloat(0x40) / 255, accuracy: 0.005)
    }

    func test_tilePosition_usable_in_set() {
        var set = Set<TilePosition>()
        set.insert(TilePosition(tileX: 3, tileY: 4))
        set.insert(TilePosition(tileX: 3, tileY: 4))
        XCTAssertEqual(set.count, 1)
    }

    func test_different_positions_distinct_in_set() {
        let set: Set<TilePosition> = [
            TilePosition(tileX: 1, tileY: 2),
            TilePosition(tileX: 2, tileY: 1),
        ]
        XCTAssertEqual(set.count, 2)
    }
}
