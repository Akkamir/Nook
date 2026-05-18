import SpriteKit
import Foundation

@MainActor
final class VillageScene: SKScene {
    private var tileMap: TileMap!
    private var villageCamera: VillageCamera!
    private var engine: VillageEngine?
    private var hud: HUD?

    // Called by ContentView when engine is available
    func configure(engine: VillageEngine) {
        self.engine = engine
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

        // Start centered on the parcelle
        villageCamera.position = CGPoint(
            x: TileMap.mapWidth / 2,
            y: TileMap.mapHeight / 2
        )

        // HUD — child of camera so it stays fixed on screen
        let hud = HUD()
        villageCamera.addChild(hud)
        self.hud = hud
        updateHUDPosition()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateHUDPosition()
    }

    private func updateHUDPosition() {
        let margin: CGFloat = 16
        // HUD top-left: camera is at center, so top-left is (-width/2, height/2)
        hud?.position = CGPoint(
            x: -size.width / 2 + margin + 80,  // 80 = half the HUD background width
            y:  size.height / 2 - margin - 16  // 16 = half the HUD background height
        )
    }

    override func willMove(from view: SKView) {
        villageCamera.detach()
    }

    override func scrollWheel(with event: NSEvent) {
        villageCamera.handleScroll(deltaY: event.deltaY)
    }

    override func update(_ currentTime: TimeInterval) {
        guard let engine else { return }
        hud?.update(totalBits: engine.totalBits)
    }
}
