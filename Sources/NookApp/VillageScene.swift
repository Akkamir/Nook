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

        // HUD is rendered via SwiftUI overlay in ContentView (more reliable with SpriteView on macOS)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateHUDPosition()
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
    }

    override func scrollWheel(with event: NSEvent) {
        villageCamera.handleScroll(deltaY: event.deltaY)
    }

    override func update(_ currentTime: TimeInterval) {
        // HUD is managed by SwiftUI overlay — nothing to update here for now
    }
}
