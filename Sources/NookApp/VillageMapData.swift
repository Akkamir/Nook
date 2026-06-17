import AppKit

struct VillageMapData {
    let mapSize: CGSize
    let tileColumns: Int
    let tileRows: Int
    let blockedTiles: Set<TilePosition>
    let backdropColor: NSColor

    static func build(from map: TiledMap, displayTileSize: CGFloat) -> VillageMapData {
        let mapSize = CGSize(
            width:  CGFloat(map.width)  * displayTileSize,
            height: CGFloat(map.height) * displayTileSize
        )

        let propLayerNames: Set<String> = ["Props (large: nature)", "Props (small: items)"]
        var blocked = Set<TilePosition>()
        for layer in map.layers
            where layer.type == "tilelayer"
               && propLayerNames.contains(layer.name)
               && layer.visible
        {
            guard let data = layer.data,
                  let W = layer.width,
                  let H = layer.height else { continue }
            for row in 0..<H {
                for col in 0..<W where data[row * W + col] > 0 {
                    blocked.insert(TilePosition(tileX: col, tileY: H - 1 - row))
                }
            }
        }

        let backdropColor: NSColor
        if let hex = map.backgroundcolor,
           let parsed = NSColor(hexString: hex) {
            backdropColor = parsed
        } else {
            backdropColor = NSColor(red: 0.22, green: 0.24, blue: 0.22, alpha: 1)
        }

        return VillageMapData(
            mapSize: mapSize,
            tileColumns: map.width,
            tileRows: map.height,
            blockedTiles: blocked,
            backdropColor: backdropColor
        )
    }

    static func build(mapURL: URL, displayTileSize: CGFloat) -> VillageMapData? {
        guard let raw = try? Data(contentsOf: mapURL),
              let map = try? JSONDecoder().decode(TiledMap.self, from: raw) else { return nil }
        return build(from: map, displayTileSize: displayTileSize)
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if hex.count == 8 { hex = String(hex.dropFirst(2)) }  // strip alpha bytes (#AARRGGBB → RRGGBB)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8)  & 0xFF) / 255,
            blue:  CGFloat( value        & 0xFF) / 255,
            alpha: 1
        )
    }
}
