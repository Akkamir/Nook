import SpriteKit

@MainActor
final class TileMap: SKNode {
    static let tileSize: CGFloat = 32
    static let gridWidth = 128
    static let gridHeight = 128
    static let mapWidth: CGFloat = CGFloat(gridWidth) * tileSize    // 4096
    static let mapHeight: CGFloat = CGFloat(gridHeight) * tileSize  // 4096

    // Central parcelle bounds (20×20 centered in 128×128)
    static let parcelleOriginX = (gridWidth - 20) / 2   // 54
    static let parcelleOriginY = (gridHeight - 20) / 2  // 54
    static let parcelleWidth = 20
    static let parcelleHeight = 20

    // Color constants (placeholders until Kenney assets arrive in Task 6)
    private static let colorGrass = NSColor(red: 0.353, green: 0.561, blue: 0.235, alpha: 1) // #5A8F3C
    private static let colorFog   = NSColor(red: 0.165, green: 0.188, blue: 0.251, alpha: 1) // #2A3040
    private static let colorTent  = NSColor(red: 0.961, green: 0.902, blue: 0.784, alpha: 1) // #F5E6C8

    func build() {
        for row in 0..<TileMap.gridHeight {
            for col in 0..<TileMap.gridWidth {
                let isGrass = col >= TileMap.parcelleOriginX &&
                              col < TileMap.parcelleOriginX + TileMap.parcelleWidth &&
                              row >= TileMap.parcelleOriginY &&
                              row < TileMap.parcelleOriginY + TileMap.parcelleHeight
                let color = isGrass ? TileMap.colorGrass : TileMap.colorFog
                let tile = SKSpriteNode(color: color,
                                        size: CGSize(width: TileMap.tileSize, height: TileMap.tileSize))
                tile.position = CGPoint(
                    x: CGFloat(col) * TileMap.tileSize + TileMap.tileSize / 2,
                    y: CGFloat(row) * TileMap.tileSize + TileMap.tileSize / 2
                )
                addChild(tile)
            }
        }

        // Tent: 2×2 tiles at center of parcelle
        let tentCol = TileMap.parcelleOriginX + TileMap.parcelleWidth / 2
        let tentRow = TileMap.parcelleOriginY + TileMap.parcelleHeight / 2
        let tent = SKSpriteNode(
            color: TileMap.colorTent,
            size: CGSize(width: TileMap.tileSize * 2, height: TileMap.tileSize * 2)
        )
        tent.position = CGPoint(
            x: CGFloat(tentCol) * TileMap.tileSize + TileMap.tileSize,
            y: CGFloat(tentRow) * TileMap.tileSize + TileMap.tileSize
        )
        addChild(tent)
    }
}
