import CoreGraphics
import Foundation

struct VillageTilePlacement: Equatable {
    let role: String
    let tileX: Int
    let tileY: Int
}

struct VillagePropPlacement: Equatable {
    let role: String
    let tileX: Int
    let tileY: Int
    let footprintWidth: Int
    let footprintHeight: Int
    let zOffset: CGFloat
}

struct VillageWorkSpot: Equatable {
    let id: String
    let homeTile: TilePosition
    let workTile: TilePosition
    let wanderTiles: [TilePosition]
}

struct VillageLayout: Equatable {
    let origin: TilePosition
    let width: Int
    let height: Int
    let tiles: [VillageTilePlacement]
    let props: [VillagePropPlacement]
    let workSpots: [VillageWorkSpot]

    @MainActor static func cozyHub() -> VillageLayout {
        let origin = TilePosition(tileX: TileMap.parcelleOriginX - 2, tileY: TileMap.parcelleOriginY - 2)
        let width = 24
        let height = 24
        let centerX = origin.tileX + width / 2
        let centerY = origin.tileY + height / 2

        var tiles: [VillageTilePlacement] = []
        for y in origin.tileY..<(origin.tileY + height) {
            for x in origin.tileX..<(origin.tileX + width) {
                let role: String
                if abs(x - centerX) <= 1 || abs(y - centerY) <= 1 {
                    role = "path"
                } else if x >= centerX - 3 && x <= centerX + 3 && y >= centerY - 3 && y <= centerY + 3 {
                    role = "plaza"
                } else {
                    role = "grass"
                }
                tiles.append(VillageTilePlacement(role: role, tileX: x, tileY: y))
            }
        }

        let props = [
            VillagePropPlacement(role: "house", tileX: origin.tileX + 3, tileY: origin.tileY + 17, footprintWidth: 3, footprintHeight: 3, zOffset: 1),
            VillagePropPlacement(role: "house", tileX: origin.tileX + 16, tileY: origin.tileY + 17, footprintWidth: 3, footprintHeight: 3, zOffset: 1),
            VillagePropPlacement(role: "market", tileX: origin.tileX + 16, tileY: origin.tileY + 5, footprintWidth: 3, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "fountain", tileX: centerX, tileY: centerY, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "bench", tileX: centerX - 4, tileY: centerY - 3, footprintWidth: 2, footprintHeight: 1, zOffset: 1),
            VillagePropPlacement(role: "bench", tileX: centerX + 4, tileY: centerY + 3, footprintWidth: 2, footprintHeight: 1, zOffset: 1),
            VillagePropPlacement(role: "lamp", tileX: centerX - 5, tileY: centerY + 5, footprintWidth: 1, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "lamp", tileX: centerX + 5, tileY: centerY - 5, footprintWidth: 1, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "tree", tileX: origin.tileX + 2, tileY: origin.tileY + 2, footprintWidth: 2, footprintHeight: 3, zOffset: 1),
            VillagePropPlacement(role: "tree", tileX: origin.tileX + 20, tileY: origin.tileY + 3, footprintWidth: 2, footprintHeight: 3, zOffset: 1),
            VillagePropPlacement(role: "tree", tileX: origin.tileX + 4, tileY: origin.tileY + 21, footprintWidth: 2, footprintHeight: 3, zOffset: 1),
            VillagePropPlacement(role: "bush", tileX: origin.tileX + 19, tileY: origin.tileY + 20, footprintWidth: 1, footprintHeight: 1, zOffset: 1),
            VillagePropPlacement(role: "fence", tileX: origin.tileX + 2, tileY: origin.tileY + 14, footprintWidth: 4, footprintHeight: 1, zOffset: 1),
            VillagePropPlacement(role: "fence", tileX: origin.tileX + 18, tileY: origin.tileY + 14, footprintWidth: 4, footprintHeight: 1, zOffset: 1)
        ]

        let workSpots = [
            VillageWorkSpot(id: "northwest", homeTile: TilePosition(tileX: origin.tileX + 4, tileY: origin.tileY + 16), workTile: TilePosition(tileX: centerX - 4, tileY: centerY + 2), wanderTiles: plazaWanderTiles(centerX: centerX, centerY: centerY)),
            VillageWorkSpot(id: "northeast", homeTile: TilePosition(tileX: origin.tileX + 17, tileY: origin.tileY + 16), workTile: TilePosition(tileX: centerX + 4, tileY: centerY + 2), wanderTiles: plazaWanderTiles(centerX: centerX, centerY: centerY)),
            VillageWorkSpot(id: "southwest", homeTile: TilePosition(tileX: origin.tileX + 5, tileY: origin.tileY + 6), workTile: TilePosition(tileX: centerX - 4, tileY: centerY - 2), wanderTiles: plazaWanderTiles(centerX: centerX, centerY: centerY)),
            VillageWorkSpot(id: "southeast", homeTile: TilePosition(tileX: origin.tileX + 17, tileY: origin.tileY + 6), workTile: TilePosition(tileX: centerX + 4, tileY: centerY - 2), wanderTiles: plazaWanderTiles(centerX: centerX, centerY: centerY))
        ]

        return VillageLayout(origin: origin, width: width, height: height, tiles: tiles, props: props, workSpots: workSpots)
    }

    private static func plazaWanderTiles(centerX: Int, centerY: Int) -> [TilePosition] {
        [
            TilePosition(tileX: centerX - 2, tileY: centerY),
            TilePosition(tileX: centerX + 2, tileY: centerY),
            TilePosition(tileX: centerX, tileY: centerY - 2),
            TilePosition(tileX: centerX, tileY: centerY + 2)
        ]
    }
}
