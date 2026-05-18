import SpriteKit

@MainActor
final class HUD: SKNode {
    private let bitsLabel = SKLabelNode(fontNamed: "Monaco")
    private let background = SKSpriteNode()
    private var lastDisplayedBits: Double = -1

    static let backgroundWidth: CGFloat = 200

    override init() {
        super.init()
        setupBackground()
        setupLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBackground() {
        background.color = NSColor(white: 0, alpha: 0.6)
        background.size = CGSize(width: HUD.backgroundWidth, height: 32)
        background.position = .zero
        addChild(background)
    }

    private func setupLabel() {
        bitsLabel.fontSize = 14
        bitsLabel.fontColor = .white
        bitsLabel.horizontalAlignmentMode = .left
        bitsLabel.verticalAlignmentMode = .center
        bitsLabel.position = CGPoint(x: -HUD.backgroundWidth / 2 + 8, y: 0) // 8pt left padding
        addChild(bitsLabel)
    }

    func update(totalBits: Double) {
        guard totalBits != lastDisplayedBits else { return }
        lastDisplayedBits = totalBits
        bitsLabel.text = "⬡ \(String(format: "%.1f", totalBits)) Bits"
        // background width is fixed (see setupBackground), no resize needed here
    }

    func animatePending(_ pending: Double) {
        guard pending > 0 else { return }
        let popup = SKLabelNode(fontNamed: "Monaco")
        popup.text = "+\(String(format: "%.1f", pending)) Bits"
        popup.fontSize = 12
        popup.fontColor = NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1) // green
        popup.position = CGPoint(x: 0, y: 24)
        popup.alpha = 0
        addChild(popup)

        let fadeIn  = SKAction.fadeIn(withDuration: 0.3)
        let rise    = SKAction.moveBy(x: 0, y: 20, duration: 0.8)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let remove  = SKAction.removeFromParent()
        let seq = SKAction.sequence([
            SKAction.group([fadeIn, rise]),
            fadeOut,
            remove
        ])
        popup.run(seq)
    }
}
