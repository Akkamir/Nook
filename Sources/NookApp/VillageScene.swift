import SpriteKit
import Foundation

@MainActor
final class VillageScene: SKScene {
    private var tileMap: TileMap!
    private var decorLayer: VillageDecorLayer?
    private var villageCamera: VillageCamera!
    private var engine: VillageEngine?
    private var hud: HUD?
    private var npcManager: NPCManager?
    private var fogSystem: FogSystem?
    private var lastAgentCount: Int = 0
    private var lastTotalBits: Double = -1
    private var lastActiveSessions: Set<String> = []
    private var lastActiveSessionCounts: [String: Int] = [:]
    private var lastDayPhase: DayPhase?
    private var initialZoomSet = false

    // Called by ContentView when engine is available
    func configure(engine: VillageEngine) {
        self.engine = engine
        npcManager = NPCManager(scene: self, engine: engine)
        npcManager?.sync()
        npcManager?.syncActiveStates(engine.activeSessions)
        lastAgentCount = engine.agents.count
        lastActiveSessions = engine.activeSessions
        lastActiveSessionCounts = engine.activeSessionCounts
        lastDayPhase = engine.dayPhase
        // Animate pending bits once on configure (app launch)
        if engine.pendingBits > 0 {
            hud?.animatePending(engine.pendingBits)
            engine.consumePendingBits()
        }
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 0)  // bottom-left origin
        view.preferredFramesPerSecond = 60

        // Camera
        villageCamera = VillageCamera()
        addChild(villageCamera)
        self.camera = villageCamera   // wire SKScene.camera property

        // Attach pan gesture recognizer to the view
        villageCamera.attach(to: view)

        // TileMap
        tileMap = TileMap()
        addChild(tileMap)
        tileMap.build()

        let decor = VillageDecorLayer()
        addChild(decor)
        decorLayer = decor

        // Start centered on the parcelle
        villageCamera.position = CGPoint(
            x: TileMap.mapWidth / 2,
            y: TileMap.mapHeight / 2
        )

        // Interim zoom before resizeFill fires — show ~40 tiles wide (parcelle + margins)
        let targetVisible: CGFloat = CGFloat(TileMap.parcelleWidth + 20) * TileMap.tileSize  // 1280
        villageCamera.setScale(targetVisible / size.width)

        // Fog
        fogSystem = FogSystem()
        addChild(fogSystem!)

        // HUD is rendered via SwiftUI overlay in ContentView (more reliable with SpriteKit on macOS)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateHUDPosition()
        // After resizeFill changes scene from 4096×4096 to view size, fix the zoom
        if !initialZoomSet, size.width > 100, size.width < TileMap.mapWidth * 0.75 {
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

    override func update(_ currentTime: TimeInterval) {
        villageCamera.clampPosition()
        if let engine, engine.agents.count != lastAgentCount {
            npcManager?.sync()
            lastAgentCount = engine.agents.count
        }
        if let engine, engine.totalBits != lastTotalBits {
            fogSystem?.update(totalBits: engine.totalBits)
            npcManager?.sync()
            lastTotalBits = engine.totalBits
        }
        if let engine, engine.activeSessions != lastActiveSessions {
            npcManager?.syncActiveStates(engine.activeSessions)
            lastActiveSessions = engine.activeSessions
        }
        if let engine, engine.activeSessionCounts != lastActiveSessionCounts {
            npcManager?.syncVisualStates()
            lastActiveSessionCounts = engine.activeSessionCounts
        }
        if let engine, engine.dayPhase != lastDayPhase {
            npcManager?.syncVisualStates()
            lastDayPhase = engine.dayPhase
        }
        if let engine, !engine.newBitEvents.isEmpty {
            npcManager?.handleBitEvents(engine.newBitEvents)
            engine.newBitEvents = []
        }
    }
}
