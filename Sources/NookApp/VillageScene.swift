import SpriteKit
import Foundation

@MainActor
final class VillageScene: SKScene {
    var onNPCSelection: ((NPCSelection?) -> Void)?
    var onLocalAssetAvailability: ((Bool) -> Void)?

    private var tileMap: TileMap!
    private var decorLayer: VillageDecorLayer?
    private var assetVillageLayer: AssetVillageLayer?
    private var tiledVillageLayer: TiledVillageLayer?
    private var villageCamera: VillageCamera!
    private var engine: VillageEngine?
    private var hud: HUD?
    private var npcManager: NPCManager?
    private var fogSystem: FogSystem?
    private var lastAgentCount: Int = 0
    private var lastTotalBits: Double = -1
    private var lastActiveSessions: Set<String> = []
    private var lastActiveSessionCounts: [String: Int] = [:]
    private var lastUpgrades: UpgradeState = .empty
    private var lastDayPhase: DayPhase?
    private var lastRoster: NPCRoster?
    private var initialZoomSet = false
    private var selectedNPCID: String?

    // Called by ContentView when engine is available
    func configure(engine: VillageEngine) {
        self.engine = engine
        npcManager = NPCManager(scene: self, engine: engine)
        if let mapURL = TiledVillageLayer.findMapURL(),
           let mapData = VillageMapData.build(mapURL: mapURL, displayTileSize: TileMap.tileSize) {
            npcManager?.setMapData(mapData)
        }
        engine.onTrickleGain = { [weak self] agentName, bits in
            self?.npcManager?.showTrickleGain(agentName: agentName, bits: bits)
        }
        engine.onLiveComment = { [weak self] agentName, line in
            self?.npcManager?.showLiveComment(agentName: agentName, line: line)
        }
        npcManager?.sync()
        npcManager?.syncActiveStates(engine.activeSessions)
        lastAgentCount = engine.agents.count
        lastActiveSessions = engine.activeSessions
        lastActiveSessionCounts = engine.activeSessionCounts
        lastDayPhase = engine.dayPhase
        lastRoster = engine.roster
        if engine.pendingBits > 0 {
            hud?.animatePending(engine.pendingBits)
            engine.consumePendingBits()
        }
    }

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 0)
        view.preferredFramesPerSecond = 60

        villageCamera = VillageCamera()
        addChild(villageCamera)
        self.camera = villageCamera

        villageCamera.attach(to: view)

        if let mapURL = TiledVillageLayer.findMapURL() {
            onLocalAssetAvailability?(true)
            let tiledLayer = TiledVillageLayer(mapURL: mapURL)
            addChild(tiledLayer)
            tiledVillageLayer = tiledLayer
            villageCamera.worldSize = tiledLayer.mapSize
        } else if let catalog = PixelAssetCatalog.loadMaygetsu() {
            onLocalAssetAvailability?(true)
            let assetLayer = AssetVillageLayer(catalog: catalog)
            addChild(assetLayer)
            assetVillageLayer = assetLayer
        } else {
            onLocalAssetAvailability?(false)
            tileMap = TileMap()
            addChild(tileMap)
            tileMap.build()
            let decor = VillageDecorLayer()
            addChild(decor)
            decorLayer = decor
        }

        backgroundColor = tiledVillageLayer?.mapData.backdropColor ?? .black

        if let tiled = tiledVillageLayer {
            villageCamera.position = tiled.mapCenter
        } else {
            villageCamera.position = CGPoint(
                x: TileMap.mapWidth / 2,
                y: TileMap.mapHeight / 2
            )
        }

        if let tiled = tiledVillageLayer {
            let sx = tiled.mapSize.width  / max(size.width,  1)
            let sy = tiled.mapSize.height / max(size.height, 1)
            villageCamera.setScale(max(sx, sy))
        } else {
            let targetVisible: CGFloat = CGFloat(TileMap.parcelleWidth + 20) * TileMap.tileSize
            villageCamera.setScale(targetVisible / size.width)
        }

        fogSystem = FogSystem()
        addChild(fogSystem!)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateHUDPosition()
        guard !initialZoomSet, size.width > 100 else { return }
        if let tiled = tiledVillageLayer {
            initialZoomSet = true
            let sx = tiled.mapSize.width  / max(size.width,  1)
            let sy = tiled.mapSize.height / max(size.height, 1)
            villageCamera.setScale(max(sx, sy))
        } else if size.width < TileMap.mapWidth * 0.75 {
            initialZoomSet = true
            let targetVisible: CGFloat = CGFloat(TileMap.parcelleWidth + 20) * TileMap.tileSize
            villageCamera.setScale(targetVisible / size.width)
        }
    }

    private func updateHUDPosition() {
        // Use the actual view bounds — scene.size lags behind during first layout
        let w = view?.bounds.width  ?? size.width
        let h = view?.bounds.height ?? size.height
        let margin: CGFloat = 16
        hud?.position = CGPoint(
            x: -w / 2 + margin + HUD.backgroundWidth / 2,
            y:  h / 2 - margin - 16
        )
    }

    override func willMove(from view: SKView) {
        villageCamera.detach()
        if let positions = npcManager?.currentPositions() {
            var state = VillagePersistence.shared.load()
            state.npcPositions = positions
            state.lastSaved = Date()
            VillagePersistence.shared.save(state)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        villageCamera.handleScroll(deltaY: event.deltaY)
    }

    func clearSelection() {
        selectedNPCID = nil
        onNPCSelection?(nil)
    }

    private func selectNPC(id: String) {
        guard let selection = npcManager?.selection(for: id) else {
            clearSelection()
            return
        }
        selectedNPCID = id
        onNPCSelection?(selection)
    }

    private func refreshSelection() {
        guard let selectedNPCID else { return }
        guard npcManager?.containsNPC(id: selectedNPCID) == true else {
            clearSelection()
            return
        }
        selectNPC(id: selectedNPCID)
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard let id = npcManager?.npcID(at: point) else {
            clearSelection()
            return
        }
        selectNPC(id: id)
    }

    override func update(_ currentTime: TimeInterval) {
        villageCamera.clampPosition()
        if let engine, engine.agents.count != lastAgentCount {
            npcManager?.sync()
            refreshSelection()
            lastAgentCount = engine.agents.count
        }
        if let engine, engine.roster != lastRoster {
            npcManager?.sync()
            refreshSelection()
            lastRoster = engine.roster
        }
        if let engine, engine.totalBitsRaw != lastTotalBits {
            fogSystem?.update(totalBits: engine.totalBitsRaw)
            npcManager?.sync()
            refreshSelection()
            lastTotalBits = engine.totalBitsRaw
        }
        if let engine, engine.activeSessions != lastActiveSessions {
            npcManager?.syncActiveStates(engine.activeSessions)
            refreshSelection()
            lastActiveSessions = engine.activeSessions
        }
        if let engine, engine.activeSessionCounts != lastActiveSessionCounts {
            npcManager?.syncVisualStates()
            refreshSelection()
            lastActiveSessionCounts = engine.activeSessionCounts
        }
        if let engine, engine.upgrades != lastUpgrades {
            // A purchase changes available bits / multiplier without moving totalBitsRaw.
            npcManager?.syncVisualStates()
            refreshSelection()
            lastUpgrades = engine.upgrades
        }
        if let engine, engine.dayPhase != lastDayPhase {
            npcManager?.syncVisualStates()
            lastDayPhase = engine.dayPhase
        }
        if let engine, !engine.newBitEvents.isEmpty {
            npcManager?.handleBitEvents(engine.newBitEvents)
            engine.newBitEvents = []
            refreshSelection()
        }
        if let engine, !engine.newActivityEvents.isEmpty {
            npcManager?.handleActivityEvents(engine.newActivityEvents)
            engine.newActivityEvents = []
        }
    }
}
