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

    private let speechComposer: SpeechLineComposing = HeuristicLineComposer()
    private var lastSpokeAt: [String: Date] = [:]
    private let speechCooldown: TimeInterval = 50

    struct TileBounds {
        let minX, minY, maxX, maxY: Int
        func contains(_ x: Int, _ y: Int) -> Bool {
            x >= minX && x <= maxX && y >= minY && y <= maxY
        }
    }

    var spawnBounds = TileBounds(
        minX: TileMap.parcelleOriginX,
        minY: TileMap.parcelleOriginY,
        maxX: TileMap.parcelleOriginX + TileMap.parcelleWidth  - 1,
        maxY: TileMap.parcelleOriginY + TileMap.parcelleHeight - 1
    )

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
            // TiledVillageLayer (z=4) + highest tile layer (z=100) + y-sort (≈2) = 106.
            // SpriteView uses ignoresSiblingOrder=true → cumulative z matters.
            // Set NPC above all tiles.
            sprite.zPosition = 200

            scene?.addChild(sprite)

            let slotIndex = sortedIDs.firstIndex(of: id) ?? sprites.count
            let behavior = NPCBehavior(sprite: sprite, model: model, deskTile: deskTile(for: slotIndex), spawnBounds: spawnBounds)
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
                if let previousBond = lastBondByAgent[id], record.bond > previousBond {
                    sprites[id]?.showBondPromotion(level: record.bond)
                }
                lastBondByAgent[id] = record.bond
                behaviors[id]?.update(model: updated)
                models[id] = updated
            }
        }
        syncVisualStates()

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

    func handleActivityEvents(_ events: [SessionActivityEvent]) {
        let now = Date()
        // Keep only the most recent event per agent with a live sprite.
        var latestByAgent: [String: SessionActivityEvent] = [:]
        for event in events {
            guard let agent = event.agentName, sprites[agent] != nil else { continue }
            if let existing = latestByAgent[agent], existing.seq > event.seq { continue }
            latestByAgent[agent] = event
        }
        for (agent, event) in latestByAgent {
            if let last = lastSpokeAt[agent], now.timeIntervalSince(last) < speechCooldown { continue }
            guard let line = speechComposer.line(for: event, session: engine.sessions[event.sessionId]) else { continue }
            sprites[agent]?.showSpeech(line)
            lastSpokeAt[agent] = now
        }
    }

    func npcID(at point: CGPoint) -> String? {
        sprites.first { _, sprite in
            sprite.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12).contains(point)
        }?.key
    }

    func selection(for id: String) -> NPCSelection? {
        guard let model = models[id] else { return nil }
        let visualState = NPCVisualState.derive(
            from: model,
            activeSessionCount: engine.activeSessionCounts[id, default: 0],
            dayPhase: engine.dayPhase
        )

        let agentSessions = engine.sessions.values.filter { $0.agentName == id }
        let projects = ProjectRollup.forAgent(Array(agentSessions))
        let recent = agentSessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
        let moments = Moment.forAgent(Array(agentSessions))
        let summary = Moment.summary(Array(agentSessions))

        return NPCSelection(
            id: id,
            name: model.name,
            bond: model.bond,
            totalTokens: model.totalTokens,
            totalBits: model.totalBits,
            activeSessionCount: visualState.sessionCount,
            trait: visualState.trait,
            projects: Array(projects.prefix(5)),
            recentSessions: Array(recent.prefix(5)),
            moments: moments,
            currentStreakDays: summary.currentStreakDays,
            longestSessionSeconds: summary.longestSessionSeconds
        )
    }

    func containsNPC(id: String) -> Bool {
        models[id] != nil
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

    private func randomSpawnTile() -> (Int, Int) {
        let b = spawnBounds
        let centerX = (b.minX + b.maxX) / 2
        let centerY = (b.minY + b.maxY) / 2
        for _ in 0..<10 {
            let tileX = Int.random(in: b.minX...b.maxX)
            let tileY = Int.random(in: b.minY...b.maxY)
            if abs(tileX - centerX) >= 2 || abs(tileY - centerY) >= 2 {
                return (tileX, tileY)
            }
        }
        return (b.minX, b.minY)
    }

    private func savedTile(for id: String) -> (Int, Int)? {
        let state = VillagePersistence.shared.load()
        guard let pos = state.npcPositions[id],
              spawnBounds.contains(pos.tileX, pos.tileY) else { return nil }
        return (pos.tileX, pos.tileY)
    }

    private func deskTile(for index: Int) -> TilePosition {
        let b = spawnBounds
        let startX = b.minX + 4
        let startY = b.maxY - 4
        let col = index % 4
        let row = index / 4
        return TilePosition(
            tileX: min(startX + col * 4, b.maxX),
            tileY: max(startY - row * 3, b.minY)
        )
    }

    func currentPositions() -> [String: TilePosition] {
        var result: [String: TilePosition] = [:]
        for (id, behavior) in behaviors {
            result[id] = behavior.currentTile()
        }
        return result
    }
}
