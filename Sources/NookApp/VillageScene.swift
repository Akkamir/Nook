import SpriteKit
import Foundation

@MainActor
final class VillageScene: SKScene {
    private var tileMap: TileMap!
    private var villageCamera: VillageCamera!
    private var engine: VillageEngine?

    // Called by ContentView when engine is available
    func configure(engine: VillageEngine) {
        self.engine = engine
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
    }

    override func willMove(from view: SKView) {
        villageCamera.detach()
    }

    override func scrollWheel(with event: NSEvent) {
        villageCamera.handleScroll(deltaY: event.deltaY)
    }

    override func update(_ currentTime: TimeInterval) {
        // future: NPC animations, weather, etc.
    }
}
