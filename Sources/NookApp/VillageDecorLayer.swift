import SpriteKit

@MainActor
final class VillageDecorLayer: SKNode {
    override init() {
        super.init()
        zPosition = 4
        buildPaths()
        buildOfficeArea()
        buildTrees()
        buildLamps()
        buildZoneMarkers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildPaths() {
        let pathColor = NSColor(red: 0.48, green: 0.36, blue: 0.22, alpha: 1)
        addChild(PixelNodeFactory.rect(
            size: CGSize(width: CGFloat(TileMap.parcelleWidth) * TileMap.tileSize, height: 3 * TileMap.tileSize),
            color: pathColor,
            position: world(tileX: TileMap.parcelleOriginX + TileMap.parcelleWidth / 2, tileY: TileMap.parcelleOriginY + TileMap.parcelleHeight / 2),
            z: 0
        ))
        addChild(PixelNodeFactory.rect(
            size: CGSize(width: 3 * TileMap.tileSize, height: CGFloat(TileMap.parcelleHeight) * TileMap.tileSize),
            color: pathColor,
            position: world(tileX: TileMap.parcelleOriginX + TileMap.parcelleWidth / 2, tileY: TileMap.parcelleOriginY + TileMap.parcelleHeight / 2),
            z: 0
        ))
    }

    private func buildOfficeArea() {
        let rug = PixelNodeFactory.rect(
            size: CGSize(width: 18 * TileMap.tileSize, height: 7 * TileMap.tileSize),
            color: NSColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1),
            position: world(tileX: TileMap.parcelleOriginX + 10, tileY: TileMap.parcelleOriginY + 15),
            z: 1
        )
        rug.alpha = 0.75
        addChild(rug)
    }

    private func buildTrees() {
        let positions = [
            TilePosition(tileX: TileMap.parcelleOriginX + 1, tileY: TileMap.parcelleOriginY + 1),
            TilePosition(tileX: TileMap.parcelleOriginX + 18, tileY: TileMap.parcelleOriginY + 2),
            TilePosition(tileX: TileMap.parcelleOriginX + 2, tileY: TileMap.parcelleOriginY + 18),
            TilePosition(tileX: TileMap.parcelleOriginX + 18, tileY: TileMap.parcelleOriginY + 18)
        ]
        for position in positions {
            addChild(tree(at: position))
        }
    }

    private func buildLamps() {
        for position in [
            TilePosition(tileX: TileMap.parcelleOriginX + 5, tileY: TileMap.parcelleOriginY + 14),
            TilePosition(tileX: TileMap.parcelleOriginX + 15, tileY: TileMap.parcelleOriginY + 14)
        ] {
            let lamp = SKNode()
            lamp.position = world(tileX: position.tileX, tileY: position.tileY)
            lamp.addChild(PixelNodeFactory.rect(
                size: CGSize(width: 6, height: 26),
                color: NSColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1),
                position: CGPoint(x: 0, y: 5),
                z: 2
            ))
            lamp.addChild(PixelNodeFactory.rect(
                size: CGSize(width: 18, height: 12),
                color: NSColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1),
                position: CGPoint(x: 0, y: 23),
                z: 3
            ))
            addChild(lamp)
        }
    }

    private func buildZoneMarkers() {
        let markers: [(String, TilePosition)] = [
            ("FOREST", TilePosition(tileX: TileMap.parcelleOriginX - 4, tileY: TileMap.parcelleOriginY + 10)),
            ("LAKE", TilePosition(tileX: TileMap.parcelleOriginX + 10, tileY: TileMap.parcelleOriginY - 4)),
            ("MARKET", TilePosition(tileX: TileMap.parcelleOriginX + 24, tileY: TileMap.parcelleOriginY + 10)),
            ("MOUNT", TilePosition(tileX: TileMap.parcelleOriginX + 10, tileY: TileMap.parcelleOriginY + 24))
        ]
        for (text, position) in markers {
            let sign = PixelNodeFactory.bubble(text: text, position: world(tileX: position.tileX, tileY: position.tileY))
            sign.setScale(0.75)
            addChild(sign)
        }
    }

    private func tree(at tile: TilePosition) -> SKNode {
        let root = SKNode()
        root.position = world(tileX: tile.tileX, tileY: tile.tileY)
        root.addChild(PixelNodeFactory.rect(
            size: CGSize(width: 10, height: 20),
            color: NSColor(red: 0.35, green: 0.20, blue: 0.10, alpha: 1),
            position: CGPoint(x: 0, y: -2),
            z: 1
        ))
        root.addChild(PixelNodeFactory.rect(
            size: CGSize(width: 34, height: 30),
            color: NSColor(red: 0.16, green: 0.42, blue: 0.22, alpha: 1),
            position: CGPoint(x: 0, y: 18),
            z: 2
        ))
        root.addChild(PixelNodeFactory.rect(
            size: CGSize(width: 24, height: 22),
            color: NSColor(red: 0.22, green: 0.56, blue: 0.28, alpha: 1),
            position: CGPoint(x: 0, y: 30),
            z: 3
        ))
        return root
    }

    private func world(tileX: Int, tileY: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(tileX) * TileMap.tileSize + TileMap.tileSize / 2,
            y: CGFloat(tileY) * TileMap.tileSize + TileMap.tileSize / 2
        )
    }
}
