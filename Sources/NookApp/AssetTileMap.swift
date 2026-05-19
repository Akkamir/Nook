import SpriteKit

@MainActor
final class AssetTileMap: SKNode {
    private let catalog: PixelAssetCatalog
    private let layout: VillageLayout

    init(catalog: PixelAssetCatalog, layout: VillageLayout) {
        self.catalog = catalog
        self.layout = layout
        super.init()
        zPosition = 1
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        for placement in layout.tiles {
            let texture = texture(for: placement.role)
            let node = SKSpriteNode(texture: texture, color: fallbackColor(for: placement.role), size: CGSize(width: TileMap.tileSize, height: TileMap.tileSize))
            node.colorBlendFactor = texture == nil ? 1 : 0
            node.position = CGPoint(
                x: CGFloat(placement.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
                y: CGFloat(placement.tileY) * TileMap.tileSize + TileMap.tileSize / 2
            )
            node.zPosition = 0
            addChild(node)
        }
    }

    private func texture(for role: String) -> SKTexture? {
        guard let entry = catalog.entry(for: role, in: .terrain) else { return nil }
        return catalog.texture(for: entry)
    }

    private func fallbackColor(for role: String) -> NSColor {
        switch role {
        case "path":
            return NSColor(red: 0.56, green: 0.43, blue: 0.28, alpha: 1)
        case "plaza":
            return NSColor(red: 0.50, green: 0.50, blue: 0.45, alpha: 1)
        case "water":
            return NSColor(red: 0.20, green: 0.47, blue: 0.68, alpha: 1)
        default:
            return NSColor(red: 0.32, green: 0.58, blue: 0.30, alpha: 1)
        }
    }
}
