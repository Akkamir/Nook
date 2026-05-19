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

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let ts = TileMap.tileSize
        for placement in layout.tiles {
            let node: SKSpriteNode
            if placement.role == "grass" {
                node = SKSpriteNode(
                    color: NSColor(red: 0.66, green: 0.75, blue: 0.44, alpha: 1),
                    size: CGSize(width: ts, height: ts)
                )
            } else if let texture = terrainTexture(for: placement.role) {
                texture.filteringMode = .nearest
                node = SKSpriteNode(texture: texture, size: CGSize(width: ts, height: ts))
            } else {
                node = SKSpriteNode(
                    color: fallbackColor(for: placement.role),
                    size: CGSize(width: ts, height: ts)
                )
            }
            node.position = CGPoint(
                x: CGFloat(placement.tileX) * ts + ts / 2,
                y: CGFloat(placement.tileY) * ts + ts / 2
            )
            node.zPosition = 0
            addChild(node)
        }
    }

    private func terrainTexture(for role: String) -> SKTexture? {
        guard let entry = catalog.entry(for: role, in: .terrain) else { return nil }
        return catalog.texture(for: entry)
    }

    private func fallbackColor(for role: String) -> NSColor {
        switch role {
        case "path":   return NSColor(red: 0.72, green: 0.65, blue: 0.55, alpha: 1)
        case "plaza":  return NSColor(red: 0.68, green: 0.68, blue: 0.63, alpha: 1)
        case "water":  return NSColor(red: 0.22, green: 0.52, blue: 0.72, alpha: 1)
        case "ground": return NSColor(red: 0.80, green: 0.72, blue: 0.60, alpha: 1)
        default:       return NSColor(red: 0.66, green: 0.75, blue: 0.44, alpha: 1)
        }
    }
}
