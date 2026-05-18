import SpriteKit

@MainActor
final class HUD: SKNode {
    private let bitsLabel = SKLabelNode(fontNamed: "Monaco")
    private let background = SKSpriteNode()

    override init() {
        super.init()
        setupBackground()
        setupLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBackground() {
        background.color = NSColor(white: 0, alpha: 0.6)
        background.size = CGSize(width: 160, height: 32)
        background.position = .zero
        addChild(background)
    }

    private func setupLabel() {
        bitsLabel.fontSize = 14
        bitsLabel.fontColor = .white
        bitsLabel.horizontalAlignmentMode = .left
        bitsLabel.verticalAlignmentMode = .center
        bitsLabel.position = CGPoint(x: -72, y: 0) // left-aligned within background
        addChild(bitsLabel)
    }

    func update(totalBits: Double) {
        bitsLabel.text = "⬡ \(String(format: "%.1f", totalBits)) Bits"
        // Resize background to fit label
        let padding: CGFloat = 16
        background.size.width = bitsLabel.frame.width + padding * 2
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
