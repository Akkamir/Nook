import SpriteKit

@MainActor
final class AssetVillageLayer: SKNode {
    private let catalog: PixelAssetCatalog
    private let layout: VillageLayout

    init(catalog: PixelAssetCatalog, layout: VillageLayout = .cozyHub()) {
        self.catalog = catalog
        self.layout = layout
        super.init()
        zPosition = 4
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        addChild(AssetTileMap(catalog: catalog, layout: layout))
        for prop in layout.props {
            addChild(propNode(for: prop))
        }
    }

    private func propNode(for prop: VillagePropPlacement) -> SKNode {
        let ts = TileMap.tileSize
        let root = SKNode()
        root.position = CGPoint(
            x: CGFloat(prop.tileX) * ts + CGFloat(prop.footprintWidth) * ts / 2,
            y: CGFloat(prop.tileY) * ts
        )
        root.zPosition = CGFloat(prop.tileY) + prop.zOffset

        if let entry = catalog.entry(for: prop.role, in: .props),
           let texture = catalog.texture(for: entry) {
            texture.filteringMode = .nearest
            // Display at native pixel size × 2 (assets are 16px native, display tile = 32px)
            let w = CGFloat(entry.tileWidth) * 2
            let h = CGFloat(entry.tileHeight) * 2
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: w, height: h))
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            root.addChild(sprite)
        } else {
            root.addChild(fallbackProp(for: prop))
        }

        return root
    }

    private func fallbackProp(for prop: VillagePropPlacement) -> SKNode {
        let root = SKNode()
        let ts = TileMap.tileSize
        let width = CGFloat(max(prop.footprintWidth, 1)) * ts
        let height = CGFloat(max(prop.footprintHeight, 1)) * ts
        switch prop.role {
        case "tree", "pinetree":
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width * 0.45, height: height * 0.42), color: NSColor(red: 0.35, green: 0.22, blue: 0.10, alpha: 1), position: CGPoint(x: 0, y: height * 0.18), z: 1))
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width, height: height * 0.62), color: NSColor(red: 0.16, green: 0.45, blue: 0.22, alpha: 1), position: CGPoint(x: 0, y: height * 0.62), z: 2))
        case "house":
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width, height: height * 0.65), color: NSColor(red: 0.66, green: 0.46, blue: 0.31, alpha: 1), position: CGPoint(x: 0, y: height * 0.28), z: 1))
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width * 1.12, height: height * 0.34), color: NSColor(red: 0.54, green: 0.18, blue: 0.16, alpha: 1), position: CGPoint(x: 0, y: height * 0.76), z: 2))
        case "lamp":
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: 6, height: height * 0.76), color: NSColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1), position: CGPoint(x: 0, y: height * 0.32), z: 1))
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: 18, height: 12), color: NSColor(red: 1.0, green: 0.80, blue: 0.38, alpha: 1), position: CGPoint(x: 0, y: height * 0.76), z: 2))
        case "bench":
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width, height: 10), color: NSColor(red: 0.45, green: 0.25, blue: 0.12, alpha: 1), position: CGPoint(x: 0, y: 10), z: 1))
        case "fountain":
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width * 0.82, height: height * 0.32), color: NSColor(red: 0.58, green: 0.60, blue: 0.66, alpha: 1), position: CGPoint(x: 0, y: height * 0.18), z: 1))
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width * 0.52, height: height * 0.52), color: NSColor(red: 0.23, green: 0.55, blue: 0.76, alpha: 1), position: CGPoint(x: 0, y: height * 0.48), z: 2))
        default:
            root.addChild(PixelNodeFactory.rect(size: CGSize(width: width, height: height * 0.5), color: NSColor(red: 0.42, green: 0.34, blue: 0.24, alpha: 1), position: CGPoint(x: 0, y: height * 0.25), z: 1))
        }
        return root
    }
}
