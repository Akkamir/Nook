import SpriteKit

@MainActor
final class FogSystem: SKNode {
    private var fogBottom: SKSpriteNode!
    private var fogTop:    SKSpriteNode!
    private var fogLeft:   SKSpriteNode!
    private var fogRight:  SKSpriteNode!
    private var revealed:  Set<String> = []

    override init() {
        super.init()

        let fogColor = NSColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1.0)

        // fogBottom: (4096, 1728) at (2048, 864)
        fogBottom = SKSpriteNode(color: fogColor, size: CGSize(width: 4096, height: 1728))
        fogBottom.position = CGPoint(x: 2048, y: 864)
        fogBottom.alpha = 0.88
        fogBottom.zPosition = 2
        addChild(fogBottom)

        // fogTop: (4096, 1728) at (2048, 3232)
        fogTop = SKSpriteNode(color: fogColor, size: CGSize(width: 4096, height: 1728))
        fogTop.position = CGPoint(x: 2048, y: 3232)
        fogTop.alpha = 0.88
        fogTop.zPosition = 2
        addChild(fogTop)

        // fogLeft: (1728, 640) at (864, 2048)
        fogLeft = SKSpriteNode(color: fogColor, size: CGSize(width: 1728, height: 640))
        fogLeft.position = CGPoint(x: 864, y: 2048)
        fogLeft.alpha = 0.88
        fogLeft.zPosition = 2
        addChild(fogLeft)

        // fogRight: (1728, 640) at (3232, 2048)
        fogRight = SKSpriteNode(color: fogColor, size: CGSize(width: 1728, height: 640))
        fogRight.position = CGPoint(x: 3232, y: 2048)
        fogRight.alpha = 0.88
        fogRight.zPosition = 2
        addChild(fogRight)

        // Restore previously revealed zones (no animation)
        let saved = VillagePersistence.shared.load()
        for zoneId in saved.revealedZones {
            switch zoneId {
            case "foret":    revealInstant(fogLeft,   id: zoneId)
            case "lac":      revealInstant(fogBottom, id: zoneId)
            case "marche":   revealInstant(fogRight,  id: zoneId)
            case "montagne": revealInstant(fogTop,    id: zoneId)
            default: break
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(totalBits: Double) {
        reveal(fogLeft,   id: "foret",    threshold: 1_000,   totalBits: totalBits)
        reveal(fogBottom, id: "lac",      threshold: 5_000,   totalBits: totalBits)
        reveal(fogRight,  id: "marche",   threshold: 10_000,  totalBits: totalBits)
        reveal(fogTop,    id: "montagne", threshold: 25_000,  totalBits: totalBits)
    }

    private func reveal(_ strip: SKSpriteNode, id: String, threshold: Double, totalBits: Double) {
        guard totalBits >= threshold, !revealed.contains(id) else { return }
        revealed.insert(id)
        strip.run(SKAction.fadeOut(withDuration: 2.0))
        var state = VillagePersistence.shared.load()
        state.revealedZones = Array(revealed)
        state.lastSaved = Date()
        VillagePersistence.shared.save(state)
    }

    private func revealInstant(_ strip: SKSpriteNode, id: String) {
        revealed.insert(id)
        strip.alpha = 0
    }
}
