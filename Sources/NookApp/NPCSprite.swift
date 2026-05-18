import SpriteKit

@MainActor
final class NPCSprite: SKNode {

    private let body: SKSpriteNode
    private let nameLabel: SKLabelNode
    private let bondLabel: SKLabelNode

    init(model: NPCModel) {
        body = SKSpriteNode(
            color: NSColor(red: 0.494, green: 0.784, blue: 0.643, alpha: 1),
            size: CGSize(width: 32, height: 32)
        )
        nameLabel = SKLabelNode(fontNamed: "Monaco")
        bondLabel = SKLabelNode(fontNamed: "Monaco")
        super.init()

        body.colorBlendFactor = 1.0
        addChild(body)

        nameLabel.fontSize = 11
        nameLabel.fontColor = .white
        nameLabel.verticalAlignmentMode = .bottom
        nameLabel.position = CGPoint(x: 0, y: 20)
        nameLabel.text = model.name
        addChild(nameLabel)

        bondLabel.fontSize = 9
        bondLabel.fontColor = NSColor(red: 0.961, green: 0.902, blue: 0.639, alpha: 1)
        bondLabel.verticalAlignmentMode = .bottom
        bondLabel.position = CGPoint(x: 0, y: 34)
        bondLabel.text = "⬡ \(model.bond)  \(formatTokens(model.totalTokens))"
        bondLabel.isHidden = model.bond < 1
        addChild(bondLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(model: NPCModel) {
        nameLabel.text = model.name
        bondLabel.text = "⬡ \(model.bond)  \(formatTokens(model.totalTokens))"
        bondLabel.isHidden = model.bond < 1
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fk", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    func setActive(_ isActive: Bool) {
        if isActive {
            body.color = NSColor(red: 0.42, green: 0.50, blue: 0.83, alpha: 1.0)
            guard action(forKey: "pulse") == nil else { return }
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 0.85, duration: 0.5),
                SKAction.scale(to: 1.0, duration: 0.5)
            ]))
            run(pulse, withKey: "pulse")
        } else {
            body.color = NSColor(red: 0.494, green: 0.784, blue: 0.643, alpha: 1.0)
            removeAction(forKey: "pulse")
            setScale(1.0)
        }
    }
}
