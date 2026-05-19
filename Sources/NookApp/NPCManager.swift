import SpriteKit

@MainActor
final class NPCManager {
    private weak var scene: SKScene?
    private let engine: VillageEngine

    private var sprites: [String: NPCSprite] = [:]
    private var behaviors: [String: NPCBehavior] = [:]
    private var lastBondByAgent: [String: Int] = [:]
    private var models:  [String: NPCModel]  = [:]
    private var activeAgents: Set<String> = []

    init(scene: SKScene, engine: VillageEngine) {
        self.scene = scene
        self.engine = engine
    }

    func sync() {
        let agentIDs = Set(engine.agents.keys)
        let spriteIDs = Set(sprites.keys)
        let sortedIDs = engine.agents.keys.sorted()

        // 1. Additions
        for (id, record) in engine.agents where !sprites.keys.contains(id) {
            let (tileX, tileY) = savedTile(for: id) ?? randomSpawnTile()

            let model = NPCModel(
                id: id,
                name: record.name,
                bond: record.bond,
                totalTokens: record.totalTokens,
                totalBits: record.totalBits,
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

            let slotIndex = sortedIDs.firstIndex(of: id) ?? sprites.count
            let behavior = NPCBehavior(sprite: sprite, model: model, deskTile: deskTile(for: slotIndex))
            let visualState = NPCVisualState.derive(
                from: model,
                activeSessionCount: engine.activeSessionCounts[id, default: 0],
                dayPhase: engine.dayPhase
            )
            sprite.apply(visualState: visualState)
            behavior.apply(visualState)

            sprites[id] = sprite
            behaviors[id] = behavior
            lastBondByAgent[id] = record.bond
            models[id]  = model
        }

        // 2. Updates
        for id in spriteIDs.intersection(agentIDs) {
            guard let record = engine.agents[id], let existing = models[id] else { continue }
            if record.bond != existing.bond || record.name != existing.name || record.totalBits != existing.totalBits {
                let delta = record.totalBits - existing.totalBits
                let currentTile = behaviors[id]?.currentTile() ?? TilePosition(tileX: existing.tileX, tileY: existing.tileY)
                let updated = NPCModel(
                    id: id,
                    name: record.name,
                    bond: record.bond,
                    totalTokens: record.totalTokens,
                    totalBits: record.totalBits,
                    tileX: currentTile.tileX,
                    tileY: currentTile.tileY
                )
                sprites[id]?.update(model: updated)
                behaviors[id]?.update(model: updated)
                if delta > 0 { sprites[id]?.showBitsGain(delta) }
                models[id] = updated
            }
        }

        // 3. Removals
        for id in spriteIDs.subtracting(agentIDs) {
            sprites[id]?.removeFromParent()
            sprites.removeValue(forKey: id)
            behaviors.removeValue(forKey: id)
            lastBondByAgent.removeValue(forKey: id)
            models.removeValue(forKey: id)
        }
    }

    func handleBitEvents(_ events: [BitEvent]) {
        // Group events by agent, then stagger animations 110ms apart
        var grouped: [String: [BitEvent]] = [:]
        for event in events {
            let key = event.agentName ?? "__global__"
            grouped[key, default: []].append(event)
        }
        for (agentName, agentEvents) in grouped {
            guard let sprite = sprites[agentName] else { continue }
            for (index, event) in agentEvents.enumerated() {
                let delay = Double(index) * 0.11
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak sprite] in
                    sprite?.showBitsGain(event.bits)
                }
            }
        }
    }

    func syncVisualStates() {
        for (id, model) in models {
            guard let sprite = sprites[id], let behavior = behaviors[id] else { continue }
            let visualState = NPCVisualState.derive(
                from: model,
                activeSessionCount: engine.activeSessionCounts[id, default: 0],
                dayPhase: engine.dayPhase
            )
            sprite.apply(visualState: visualState)
            behavior.apply(visualState)
        }
    }

    func syncActiveStates(_ active: Set<String>) {
        guard active != activeAgents else { return }
        activeAgents = active
        syncVisualStates()
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

    private func deskTile(for index: Int) -> TilePosition {
        let startX = TileMap.parcelleOriginX + 4
        let startY = TileMap.parcelleOriginY + TileMap.parcelleHeight - 5
        let col = index % 4
        let row = index / 4
        return TilePosition(tileX: startX + col * 4, tileY: startY - row * 3)
    }

    func currentPositions() -> [String: TilePosition] {
        var result: [String: TilePosition] = [:]
        for (id, behavior) in behaviors {
            result[id] = behavior.currentTile()
        }
        return result
    }
}
