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

    // Visible desks for NPCs that have earned one (bond ≥ DeskPolicy.bondThreshold).
    private var desks: [String: SKNode] = [:]
    private var deskTiles: [String: TilePosition] = [:]
    private var walkableDeskCandidates: [TilePosition] = []
    private let assetCatalog = PixelAssetCatalog.loadMaygetsu()

    private let speechComposer: SpeechLineComposing = HeuristicLineComposer()
    private var lastSpokeAt: [String: Date] = [:]
    private let speechCooldown: TimeInterval = 20

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
                totalBitsRaw: record.totalBitsRaw,
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
            let desk = deskTile(for: slotIndex)
            deskTiles[id] = desk
            let behavior = NPCBehavior(sprite: sprite, model: model, deskTile: desk, spawnBounds: spawnBounds)
            let visualState = NPCVisualState.derive(
                from: model,
                activeSessionCount: engine.activeSessionCounts[id, default: 0],
                dayPhase: engine.dayPhase,
                availableBits: engine.availableBits(for: id),
                bitMultiplier: engine.bitMultiplier(for: id)
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
            if record.bond != existing.bond || record.name != existing.name || record.totalBitsRaw != existing.totalBitsRaw {
                let currentTile = behaviors[id]?.currentTile() ?? TilePosition(tileX: existing.tileX, tileY: existing.tileY)
                let updated = NPCModel(
                    id: id,
                    name: record.name,
                    bond: record.bond,
                    totalTokens: record.totalTokens,
                    totalBitsRaw: record.totalBitsRaw,
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
            deskTiles.removeValue(forKey: id)
        }

        syncDesks()
    }

    /// Places a permanent desk at each NPC's work tile once it reaches the bond
    /// threshold, and removes it if the NPC loses its desk or leaves the village.
    private func syncDesks() {
        for (id, model) in models {
            let shouldHaveDesk = DeskPolicy.hasDesk(bond: model.bond)
            if shouldHaveDesk, desks[id] == nil, let tile = deskTiles[id] {
                let desk = makeDesk(at: tile)
                scene?.addChild(desk)
                desks[id] = desk
            } else if !shouldHaveDesk, let desk = desks[id] {
                desk.removeFromParent()
                desks.removeValue(forKey: id)
            }
        }
        for id in Set(desks.keys).subtracting(models.keys) {
            desks[id]?.removeFromParent()
            desks.removeValue(forKey: id)
        }
    }

    private func makeDesk(at tile: TilePosition) -> SKNode {
        let ts = TileMap.tileSize
        let scale: CGFloat = 2
        let layout = DeskLayout.front(
            tileSize: ts,
            displayScale: scale,
            characterHeight: 64,
            deskPixelSize: CGSize(width: 48, height: 32),
            pcPixelSize: CGSize(width: 16, height: 32)
        )
        let node = SKNode()
        // Sit the desk in front of the NPC (lower on screen) and draw it above the
        // agent (z > 200) so the NPC reads as seated behind it, working at the surface.
        node.position = CGPoint(
            x: CGFloat(tile.tileX) * ts + ts / 2,
            y: CGFloat(tile.tileY) * ts + ts / 2 + layout.deskNodeYOffset
        )
        node.zPosition = 250

        if let texture = assetCatalog?.texture(relativePath: "pixel-agents/furniture/DESK/DESK_FRONT.png") {
            texture.filteringMode = .nearest
            let sprite = SKSpriteNode(
                texture: texture,
                size: CGSize(width: 48 * scale, height: 32 * scale)
            )
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.addChild(sprite)
        } else {
            node.addChild(PixelNodeFactory.rect(
                size: CGSize(width: ts * 1.6, height: ts * 0.7),
                color: NSColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1),
                position: CGPoint(x: 0, y: ts * 0.2),
                z: 1
            ))
        }
        addComputer(to: node, layout: layout)
        return node
    }

    private func addComputer(to node: SKNode, layout: DeskLayout) {
        guard let texture = assetCatalog?.texture(relativePath: "pixel-agents/furniture/PC/PC_BACK.png") else {
            node.addChild(PixelNodeFactory.rect(
                size: CGSize(width: 18, height: 16),
                color: NSColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1),
                position: layout.pcPosition,
                z: 3
            ))
            return
        }

        let computer = SKSpriteNode(
            texture: texture,
            size: CGSize(width: 16, height: 32)
        )
        computer.anchorPoint = CGPoint(x: 0.5, y: 0)
        computer.position = layout.pcPosition
        computer.zPosition = 3
        node.addChild(computer)
    }

    func handleBitEvents(_ events: [BitEvent]) {
        // Group rapid gains into one readable burst per NPC.
        // Display the effective amount (raw bits × multiplier) so the animation
        // reflects what was actually credited to the player's balance.
        var grouped: [String: Double] = [:]
        for event in events {
            let key = event.agentName ?? "__global__"
            let mult = engine.effectiveMultiplier(for: key)
            grouped[key, default: 0] += event.rawBits * mult
        }
        for (agentName, bits) in grouped {
            guard let sprite = sprites[agentName] else { continue }
            sprite.showBitsGain(bits)
            sprite.showVillageGain(bits * EconomyEngine.villageBonusRate)
        }
    }

    func showTrickleGain(agentName: String, bits: Double) {
        sprites[agentName]?.showBitsGain(bits)
    }

    func showLiveComment(agentName: String, line: String) {
        let now = Date()
        guard lastSpokeAt[agentName].map({ now.timeIntervalSince($0) >= speechCooldown }) ?? true else { return }
        sprites[agentName]?.showSpeech(line)
        lastSpokeAt[agentName] = now
    }

    func handleActivityEvents(_ events: [SessionActivityEvent]) {
        let now = Date()
        // Collect all valid events per agent; pick one at random so fast batches
        // don't always show the last event kind (e.g. always "deepWork").
        var byAgent: [String: [SessionActivityEvent]] = [:]
        for event in events {
            guard let agent = event.agentName, sprites[agent] != nil else { continue }
            byAgent[agent, default: []].append(event)
        }
        for (agent, agentEvents) in byAgent {
            if let last = lastSpokeAt[agent], now.timeIntervalSince(last) < speechCooldown { continue }
            guard let event = agentEvents.randomElement() else { continue }
            // Prefer an LLM-enriched cached line for this session when available;
            // fall back to the deterministic heuristic composer.
            let line = enrichedLine(for: event)
                ?? speechComposer.line(for: event, session: engine.sessions[event.sessionId])
            guard let line else { continue }
            sprites[agent]?.showSpeech(line)
            lastSpokeAt[agent] = now
        }
    }

    /// Picks one of the LLM-generated `cachedLines` for the event's session,
    /// rotating by event seq so repeated activity doesn't always say the same thing.
    private func enrichedLine(for event: SessionActivityEvent) -> String? {
        let lines = engine.npcMemory.sessions[event.sessionId]?.cachedLines ?? []
        let usable = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return nil }
        return usable[abs(event.seq) % usable.count]
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
        let moments = Moment.forAgent(
            Array(agentSessions),
            currentBond: model.bond,
            totalTokens: model.totalTokens
        )
        let summary = Moment.summary(Array(agentSessions))

        return NPCSelection(
            id: id,
            name: model.name,
            bond: model.bond,
            totalTokens: model.totalTokens,
            totalBitsRaw: model.totalBitsRaw,
            availableBits: engine.availableBits(for: id),
            bitMultiplier: engine.bitMultiplier(for: id),
            activeSessionCount: visualState.sessionCount,
            trait: visualState.trait,
            projects: Array(projects.prefix(5)),
            recentSessions: Array(recent.prefix(5)),
            sessionMemories: engine.npcMemory.sessions,
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
                dayPhase: engine.dayPhase,
                availableBits: engine.availableBits(for: id),
                bitMultiplier: engine.bitMultiplier(for: id)
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

    func setMapData(_ mapData: VillageMapData) {
        let border = 2
        spawnBounds = TileBounds(
            minX: border,
            minY: border,
            maxX: mapData.tileColumns - 1 - border,
            maxY: mapData.tileRows   - 1 - border
        )
        computeWalkableDeskCandidates(blocked: mapData.blockedTiles)
    }

    private func computeWalkableDeskCandidates(blocked: Set<TilePosition>) {
        let b = spawnBounds
        var candidates: [TilePosition] = []
        for y in stride(from: b.maxY, through: b.minY, by: -1) {
            for x in b.minX...b.maxX {
                let tile = TilePosition(tileX: x, tileY: y)
                guard !blocked.contains(tile) else { continue }
                candidates.append(tile)
            }
        }
        // Greedy spacing: no two candidates within 2 tiles of each other
        var spaced: [TilePosition] = []
        for candidate in candidates {
            let tooClose = spaced.contains {
                abs($0.tileX - candidate.tileX) <= 2 && abs($0.tileY - candidate.tileY) <= 2
            }
            if !tooClose { spaced.append(candidate) }
        }
        walkableDeskCandidates = spaced
    }

    private func deskTile(for index: Int) -> TilePosition {
        guard !walkableDeskCandidates.isEmpty else {
            let b = spawnBounds
            let col = index % 4
            let row = index / 4
            return TilePosition(
                tileX: min(b.minX + 4 + col * 4, b.maxX),
                tileY: max(b.maxY - 4 - row * 3, b.minY)
            )
        }
        return walkableDeskCandidates[index % walkableDeskCandidates.count]
    }

    func currentPositions() -> [String: TilePosition] {
        var result: [String: TilePosition] = [:]
        for (id, behavior) in behaviors {
            result[id] = behavior.currentTile()
        }
        return result
    }
}
