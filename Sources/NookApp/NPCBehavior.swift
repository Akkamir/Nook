import SpriteKit

@MainActor
final class NPCBehavior {
    private let sprite: NPCSprite
    private var model: NPCModel
    private let deskTile: TilePosition
    private var spawnBounds: NPCManager.TileBounds
    private var currentActivity: NPCActivityKind?
    private var currentDeskEligibility: Bool?
    private var lastDirection: Int = 0
    private var workAnchor: TilePosition?

    init(sprite: NPCSprite, model: NPCModel, deskTile: TilePosition, spawnBounds: NPCManager.TileBounds) {
        self.sprite = sprite
        self.model = model
        self.deskTile = deskTile
        self.spawnBounds = spawnBounds
    }

    func update(model: NPCModel) {
        self.model.name = model.name
        self.model.bond = model.bond
        self.model.totalTokens = model.totalTokens
        self.model.totalBits = model.totalBits
    }

    func apply(_ visualState: NPCVisualState) {
        let hasDesk = DeskPolicy.hasDesk(bond: model.bond)
        guard visualState.activity != currentActivity || hasDesk != currentDeskEligibility else { return }
        currentActivity = visualState.activity
        currentDeskEligibility = hasDesk
        sprite.removeAction(forKey: "behavior")
        sprite.removeAction(forKey: "behaviorMove")

        switch visualState.activity {
        case .working:
            if hasDesk {
                // Earned a desk: walk to the fixed work tile and type there.
                moveTo(tile: deskTile, speed: 0.18, key: "behaviorMove",
                       walkAnim: true, onArrival: { [weak self] in self?.sprite.resumeWorkPose() })
            } else {
                // No desk yet: work near the current spot with a small back-and-forth.
                startWorkWander()
            }
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

    private func startWorkWander() {
        workAnchor = currentTile()
        sprite.resumeWorkPose()
        let wait = SKAction.wait(forDuration: 2.8, withRange: 1.8)
        let step = SKAction.run { [weak self] in self?.workStep() }
        sprite.run(.repeatForever(.sequence([wait, step])), withKey: "behavior")
    }

    private func workStep() {
        guard let anchor = workAnchor else { return }
        let radius = 2
        let b = spawnBounds
        let newTile = TilePosition(
            tileX: (model.tileX + Int.random(in: -1...1))
                .clamped(to: (anchor.tileX - radius)...(anchor.tileX + radius))
                .clamped(to: b.minX...b.maxX),
            tileY: (model.tileY + Int.random(in: -1...1))
                .clamped(to: (anchor.tileY - radius)...(anchor.tileY + radius))
                .clamped(to: b.minY...b.maxY)
        )
        let dx = newTile.tileX - model.tileX
        let dy = newTile.tileY - model.tileY
        guard dx != 0 || dy != 0 else { sprite.resumeWorkPose(); return }
        moveTo(tile: newTile, speed: 0.26, key: "behaviorMove",
               walkAnim: true, onArrival: { [weak self] in self?.sprite.resumeWorkPose() })
    }

    private func randomStep(maxOffset: Int = 2) {
        let offsetX = Int.random(in: -maxOffset...maxOffset)
        let offsetY = Int.random(in: -maxOffset...maxOffset)
        let b = spawnBounds
        let newTile = TilePosition(
            tileX: (model.tileX + offsetX).clamped(to: b.minX...b.maxX),
            tileY: (model.tileY + offsetY).clamped(to: b.minY...b.maxY)
        )
        let dx = newTile.tileX - model.tileX
        let dy = newTile.tileY - model.tileY
        guard dx != 0 || dy != 0 else { return }
        moveTo(tile: newTile, speed: 0.24, key: "behaviorMove",
               walkAnim: true, onArrival: { [weak self] in self?.sprite.stopWalking() })
    }

    private func moveTo(tile: TilePosition, speed: Double, key: String,
                        walkAnim: Bool = false, onArrival: (() -> Void)? = nil) {
        let point = CGPoint(
            x: CGFloat(tile.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
            y: CGFloat(tile.tileY) * TileMap.tileSize + TileMap.tileSize / 2
        )
        let dx = tile.tileX - model.tileX
        let dy = tile.tileY - model.tileY
        let duration = Double(max(abs(dx), abs(dy))) * speed
        model.tileX = tile.tileX
        model.tileY = tile.tileY

        if walkAnim {
            let dir = direction(dx: dx, dy: dy)
            lastDirection = dir
            sprite.startWalking(direction: dir)
        }

        let move = SKAction.move(to: point, duration: max(duration, 0.1))
        if let onArrival {
            sprite.run(.sequence([move, .run(onArrival)]), withKey: key)
        } else {
            sprite.run(move, withKey: key)
        }
    }

    private func direction(dx: Int, dy: Int) -> Int {
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? 2 : 1   // right or left
        } else {
            return dy > 0 ? 3 : 0    // up or down
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
