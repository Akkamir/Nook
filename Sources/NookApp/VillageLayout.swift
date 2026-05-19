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
        let width = 20
        let height = 20
        let cx = origin.tileX + width / 2   // centre x
        let cy = origin.tileY + height / 2  // centre y

        var tiles: [VillageTilePlacement] = []
        for y in origin.tileY..<(origin.tileY + height) {
            for x in origin.tileX..<(origin.tileX + width) {
                let dx = x - cx
                let dy = y - cy
                let role: String
                // Cross path (2 tiles wide) + Plaza 4×4 at centre
                if abs(dx) <= 1 && abs(dy) <= 1 {
                    role = "plaza"
                } else if abs(dx) <= 1 || abs(dy) <= 1 {
                    role = "path"
                } else if abs(dx) <= 3 && abs(dy) <= 3 {
                    role = "plaza"
                } else {
                    role = "grass"
                }
                tiles.append(VillageTilePlacement(role: role, tileX: x, tileY: y))
            }
        }

        let props: [VillagePropPlacement] = [
            // Fontaine au centre
            VillagePropPlacement(role: "fountain", tileX: cx - 1, tileY: cy - 1, footprintWidth: 2, footprintHeight: 2, zOffset: 2),
            // Maisons dans les coins hauts
            VillagePropPlacement(role: "house", tileX: origin.tileX, tileY: origin.tileY + 13, footprintWidth: 3, footprintHeight: 5, zOffset: 1),
            VillagePropPlacement(role: "house", tileX: origin.tileX + 14, tileY: origin.tileY + 13, footprintWidth: 3, footprintHeight: 5, zOffset: 1),
            // Marché
            VillagePropPlacement(role: "market", tileX: cx + 4, tileY: origin.tileY + 14, footprintWidth: 3, footprintHeight: 4, zOffset: 1),
            // Arbres dans les coins herbe
            VillagePropPlacement(role: "tree", tileX: origin.tileX, tileY: origin.tileY + 5, footprintWidth: 3, footprintHeight: 5, zOffset: 1),
            VillagePropPlacement(role: "tree", tileX: origin.tileX + 15, tileY: origin.tileY + 5, footprintWidth: 3, footprintHeight: 5, zOffset: 1),
            VillagePropPlacement(role: "pinetree", tileX: origin.tileX, tileY: origin.tileY, footprintWidth: 3, footprintHeight: 5, zOffset: 1),
            VillagePropPlacement(role: "pinetree", tileX: origin.tileX + 15, tileY: origin.tileY, footprintWidth: 3, footprintHeight: 5, zOffset: 1),
            // Bancs de chaque côté de la plaza
            VillagePropPlacement(role: "bench", tileX: cx - 4, tileY: cy - 2, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "bench", tileX: cx + 2, tileY: cy - 2, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            // Lampadaires
            VillagePropPlacement(role: "lamp", tileX: cx - 4, tileY: cy + 2, footprintWidth: 1, footprintHeight: 4, zOffset: 1),
            VillagePropPlacement(role: "lamp", tileX: cx + 4, tileY: cy + 2, footprintWidth: 1, footprintHeight: 4, zOffset: 1),
            // Buissons aux coins de la plaza
            VillagePropPlacement(role: "bush", tileX: cx - 5, tileY: cy - 5, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "bush", tileX: cx + 3, tileY: cy - 5, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "bush", tileX: cx - 5, tileY: cy + 3, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "bush", tileX: cx + 3, tileY: cy + 3, footprintWidth: 2, footprintHeight: 2, zOffset: 1),
            // Table et flowerbed pour work spots
            VillagePropPlacement(role: "table", tileX: cx - 3, tileY: cy + 4, footprintWidth: 3, footprintHeight: 2, zOffset: 1),
            VillagePropPlacement(role: "flowerbed", tileX: cx + 1, tileY: cy + 4, footprintWidth: 2, footprintHeight: 1, zOffset: 1),
        ]

        let workSpots = [
            VillageWorkSpot(
                id: "nw",
                homeTile: TilePosition(tileX: origin.tileX + 1, tileY: origin.tileY + 14),
                workTile: TilePosition(tileX: cx - 3, tileY: cy + 4),
                wanderTiles: plazaWanderTiles(centerX: cx, centerY: cy)
            ),
            VillageWorkSpot(
                id: "ne",
                homeTile: TilePosition(tileX: origin.tileX + 15, tileY: origin.tileY + 14),
                workTile: TilePosition(tileX: cx + 2, tileY: cy + 4),
                wanderTiles: plazaWanderTiles(centerX: cx, centerY: cy)
            ),
            VillageWorkSpot(
                id: "sw",
                homeTile: TilePosition(tileX: origin.tileX + 5, tileY: origin.tileY + 4),
                workTile: TilePosition(tileX: cx - 3, tileY: cy - 4),
                wanderTiles: plazaWanderTiles(centerX: cx, centerY: cy)
            ),
            VillageWorkSpot(
                id: "se",
                homeTile: TilePosition(tileX: origin.tileX + 14, tileY: origin.tileY + 4),
                workTile: TilePosition(tileX: cx + 2, tileY: cy - 4),
                wanderTiles: plazaWanderTiles(centerX: cx, centerY: cy)
            ),
        ]

        return VillageLayout(origin: origin, width: width, height: height, tiles: tiles, props: props, workSpots: workSpots)
    }

    private static func plazaWanderTiles(centerX: Int, centerY: Int) -> [TilePosition] {
        [
            TilePosition(tileX: centerX - 2, tileY: centerY),
            TilePosition(tileX: centerX + 2, tileY: centerY),
            TilePosition(tileX: centerX, tileY: centerY - 2),
            TilePosition(tileX: centerX, tileY: centerY + 2),
        ]
    }
}
