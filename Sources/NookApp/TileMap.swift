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

    func build() {
        // TODO(Task 6 done): SKTileMapNode would be faster, but individual nodes work for prototype
        for row in 0..<TileMap.gridHeight {
            for col in 0..<TileMap.gridWidth {
                let isGrass = col >= TileMap.parcelleOriginX &&
                              col < TileMap.parcelleOriginX + TileMap.parcelleWidth &&
                              row >= TileMap.parcelleOriginY &&
                              row < TileMap.parcelleOriginY + TileMap.parcelleHeight
                let imageName = isGrass ? "grass" : "dirt"
                let tile = SKSpriteNode(imageNamed: imageName)
                tile.size = CGSize(width: TileMap.tileSize, height: TileMap.tileSize)
                tile.texture?.filteringMode = .nearest  // pixel-perfect, no bilinear blur
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
        let tent = SKSpriteNode(imageNamed: "tent")
        tent.size = CGSize(width: TileMap.tileSize * 2, height: TileMap.tileSize * 2)
        tent.texture?.filteringMode = .nearest
        tent.position = CGPoint(
            x: CGFloat(tentCol) * TileMap.tileSize + TileMap.tileSize,
            y: CGFloat(tentRow) * TileMap.tileSize + TileMap.tileSize
        )
        addChild(tent)
    }
}
