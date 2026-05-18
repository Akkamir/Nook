import SpriteKit

@MainActor
final class NPCWander {
    private let sprite: NPCSprite
    private var model: NPCModel

    init(sprite: NPCSprite, model: NPCModel) {
        self.sprite = sprite
        self.model = model
    }

    func start() {
        let wait = SKAction.wait(forDuration: 2.0, withRange: 2.5)
        let move = SKAction.run { [weak self] in
            self?.step()
        }
        let sequence = SKAction.sequence([wait, move])
        sprite.run(SKAction.repeatForever(sequence))
    }

    func stop() {
        sprite.removeAllActions()
    }

    private func step() {
        let offsetX = Int.random(in: -2...2)
        let offsetY = Int.random(in: -2...2)

        let newTileX = (model.tileX + offsetX).clamped(
            to: TileMap.parcelleOriginX...(TileMap.parcelleOriginX + TileMap.parcelleWidth - 1)
        )
        let newTileY = (model.tileY + offsetY).clamped(
            to: TileMap.parcelleOriginY...(TileMap.parcelleOriginY + TileMap.parcelleHeight - 1)
        )

        guard newTileX != model.tileX || newTileY != model.tileY else { return }

        let wx = CGFloat(newTileX) * TileMap.tileSize + TileMap.tileSize / 2
        let wy = CGFloat(newTileY) * TileMap.tileSize + TileMap.tileSize / 2

        let dx = newTileX - model.tileX
        let dy = newTileY - model.tileY
        let duration = Double(max(abs(dx), abs(dy))) * 0.35

        sprite.run(SKAction.move(to: CGPoint(x: wx, y: wy), duration: duration))

        model.tileX = newTileX
        model.tileY = newTileY
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
