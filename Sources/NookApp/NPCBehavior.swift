import SpriteKit

@MainActor
final class NPCBehavior {
    private let sprite: NPCSprite
    private var model: NPCModel
    private let deskTile: TilePosition
    private var currentActivity: NPCActivityKind?

    init(sprite: NPCSprite, model: NPCModel, deskTile: TilePosition) {
        self.sprite = sprite
        self.model = model
        self.deskTile = deskTile
    }

    func update(model: NPCModel) {
        self.model.name = model.name
        self.model.bond = model.bond
        self.model.totalTokens = model.totalTokens
        self.model.totalBits = model.totalBits
    }

    func apply(_ visualState: NPCVisualState) {
        guard visualState.activity != currentActivity else { return }
        currentActivity = visualState.activity
        sprite.removeAction(forKey: "behavior")
        sprite.removeAction(forKey: "behaviorMove")

        switch visualState.activity {
        case .working:
            moveTo(tile: deskTile, speed: 0.18, key: "behaviorMove")
        case .resting:
            startResting()
        case .wandering:
            startWandering()
        }
    }

    func currentTile() -> TilePosition {
        TilePosition(
            tileX: Int(sprite.position.x / TileMap.tileSize),
            tileY: Int(sprite.position.y / TileMap.tileSize)
        )
    }

    private func startWandering() {
        let wait = SKAction.wait(forDuration: 1.8, withRange: 1.2)
        let step = SKAction.run { [weak self] in self?.randomStep() }
        sprite.run(.repeatForever(.sequence([wait, step])), withKey: "behavior")
    }

    private func startResting() {
        let wait = SKAction.wait(forDuration: 3.0, withRange: 2.0)
        let tinyMove = SKAction.run { [weak self] in self?.randomStep(maxOffset: 1) }
        sprite.run(.repeatForever(.sequence([wait, tinyMove])), withKey: "behavior")
    }

    private func randomStep(maxOffset: Int = 2) {
        let offsetX = Int.random(in: -maxOffset...maxOffset)
        let offsetY = Int.random(in: -maxOffset...maxOffset)
        let newTile = TilePosition(
            tileX: (model.tileX + offsetX).clamped(to: TileMap.parcelleOriginX...(TileMap.parcelleOriginX + TileMap.parcelleWidth - 1)),
            tileY: (model.tileY + offsetY).clamped(to: TileMap.parcelleOriginY...(TileMap.parcelleOriginY + TileMap.parcelleHeight - 1))
        )
        guard newTile.tileX != model.tileX || newTile.tileY != model.tileY else { return }
        moveTo(tile: newTile, speed: 0.24, key: "behaviorMove")
    }

    private func moveTo(tile: TilePosition, speed: Double, key: String) {
        let point = CGPoint(
            x: CGFloat(tile.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
            y: CGFloat(tile.tileY) * TileMap.tileSize + TileMap.tileSize / 2
        )
        let dx = tile.tileX - model.tileX
        let dy = tile.tileY - model.tileY
        let duration = Double(max(abs(dx), abs(dy))) * speed
        model.tileX = tile.tileX
        model.tileY = tile.tileY
        sprite.run(SKAction.move(to: point, duration: max(duration, 0.1)), withKey: key)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
