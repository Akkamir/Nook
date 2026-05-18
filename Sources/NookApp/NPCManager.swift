import SpriteKit

@MainActor
final class NPCManager {
    private weak var scene: SKScene?
    private let engine: VillageEngine

    private var sprites: [String: NPCSprite] = [:]
    private var wanders: [String: NPCWander] = [:]
    private var models:  [String: NPCModel]  = [:]
    private var activeAgents: Set<String> = []

    init(scene: SKScene, engine: VillageEngine) {
        self.scene = scene
        self.engine = engine
    }

    func sync() {
        let agentIDs = Set(engine.agents.keys)
        let spriteIDs = Set(sprites.keys)

        // 1. Additions
        for (id, record) in engine.agents where !sprites.keys.contains(id) {
            let (tileX, tileY) = savedTile(for: id) ?? randomSpawnTile()

            let model = NPCModel(
                id: id,
                name: record.name,
                bond: record.bond,
                totalTokens: record.totalTokens,
                tileX: tileX,
                tileY: tileY
            )

            let sprite = NPCSprite(model: model)
            sprite.position = CGPoint(
                x: CGFloat(model.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
                y: CGFloat(model.tileY) * TileMap.tileSize + TileMap.tileSize / 2
            )
            sprite.zPosition = 10

            scene?.addChild(sprite)

            let wander = NPCWander(sprite: sprite, model: model)
            if activeAgents.contains(id) {
                sprite.setActive(true)
            } else {
                wander.start()
            }

            sprites[id] = sprite
            wanders[id] = wander
            models[id]  = model
        }

        // 2. Updates
        for id in spriteIDs.intersection(agentIDs) {
            guard let record = engine.agents[id], let existing = models[id] else { continue }
            if record.bond != existing.bond || record.name != existing.name || record.totalTokens != existing.totalTokens {
                let updated = NPCModel(
                    id: id,
                    name: record.name,
                    bond: record.bond,
                    totalTokens: record.totalTokens,
                    tileX: existing.tileX,
                    tileY: existing.tileY
                )
                sprites[id]?.update(model: updated)
                models[id] = updated
            }
        }

        // 3. Removals
        for id in spriteIDs.subtracting(agentIDs) {
            wanders[id]?.stop()
            sprites[id]?.removeFromParent()
            sprites.removeValue(forKey: id)
            wanders.removeValue(forKey: id)
            models.removeValue(forKey: id)
        }
    }

    func syncActiveStates(_ active: Set<String>) {
        guard active != activeAgents else { return }
        let previous = activeAgents
        activeAgents = active
        for (id, sprite) in sprites {
            let wasActive = previous.contains(id)
            let isActive = active.contains(id)
            guard wasActive != isActive else { continue }
            if isActive {
                wanders[id]?.stop()
                sprite.setActive(true)
            } else {
                sprite.setActive(false)
                wanders[id]?.start()
            }
        }
    }

    // Returns a random tile within the parcelle, avoiding a 2-tile radius around the tent center.
    private func randomSpawnTile() -> (Int, Int) {
        let centerX = TileMap.parcelleOriginX + TileMap.parcelleWidth / 2   // 64
        let centerY = TileMap.parcelleOriginY + TileMap.parcelleHeight / 2  // 64

        let minX = TileMap.parcelleOriginX
        let maxX = TileMap.parcelleOriginX + TileMap.parcelleWidth - 1
        let minY = TileMap.parcelleOriginY
        let maxY = TileMap.parcelleOriginY + TileMap.parcelleHeight - 1

        for _ in 0..<10 {
            let tileX = Int.random(in: minX...maxX)
            let tileY = Int.random(in: minY...maxY)
            if abs(tileX - centerX) >= 2 || abs(tileY - centerY) >= 2 {
                return (tileX, tileY)
            }
        }

        // Fallback: corner of the parcelle, guaranteed outside exclusion zone
        return (minX, minY)
    }

    private func savedTile(for id: String) -> (Int, Int)? {
        let state = VillagePersistence.shared.load()
        guard let pos = state.npcPositions[id] else { return nil }
        return (pos.tileX, pos.tileY)
    }

    func currentPositions() -> [String: TilePosition] {
        var result: [String: TilePosition] = [:]
        for (id, sprite) in sprites {
            let tileX = Int(sprite.position.x / TileMap.tileSize)
            let tileY = Int(sprite.position.y / TileMap.tileSize)
            result[id] = TilePosition(tileX: tileX, tileY: tileY)
        }
        return result
    }
}
