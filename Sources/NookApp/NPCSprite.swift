import SpriteKit

@MainActor
final class NPCSprite: SKNode {
    private let shadow: SKSpriteNode
    private let leftFoot: SKSpriteNode
    private let rightFoot: SKSpriteNode
    private let body: SKSpriteNode
    private let head: SKSpriteNode
    private let hair: SKSpriteNode
    private let accessory: SKSpriteNode
    private let desk: SKNode
    private let statusBubble = SKNode()
    private let nameLabel: SKLabelNode
    private let bondLabel: SKLabelNode
    private var currentVisualState: NPCVisualState?

    init(model: NPCModel) {
        shadow = PixelNodeFactory.rect(
            size: CGSize(width: 34, height: 10),
            color: NSColor.black.withAlphaComponent(0.35),
            position: CGPoint(x: 0, y: -15),
            z: -2
        )
        leftFoot = PixelNodeFactory.rect(
            size: CGSize(width: 8, height: 8),
            color: NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1),
            position: CGPoint(x: -7, y: -12),
            z: 1
        )
        rightFoot = PixelNodeFactory.rect(
            size: CGSize(width: 8, height: 8),
            color: NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1),
            position: CGPoint(x: 7, y: -12),
            z: 1
        )
        body = PixelNodeFactory.rect(
            size: CGSize(width: 22, height: 24),
            color: NSColor(red: 0.31, green: 0.62, blue: 0.78, alpha: 1),
            position: CGPoint(x: 0, y: -1),
            z: 2
        )
        head = PixelNodeFactory.rect(
            size: CGSize(width: 20, height: 18),
            color: NSColor(red: 0.93, green: 0.75, blue: 0.58, alpha: 1),
            position: CGPoint(x: 0, y: 18),
            z: 3
        )
        hair = PixelNodeFactory.rect(
            size: CGSize(width: 22, height: 7),
            color: NSColor(red: 0.17, green: 0.10, blue: 0.07, alpha: 1),
            position: CGPoint(x: 0, y: 27),
            z: 4
        )
        accessory = PixelNodeFactory.rect(
            size: CGSize(width: 24, height: 4),
            color: .clear,
            position: CGPoint(x: 0, y: 18),
            z: 5
        )
        desk = SKNode()
        nameLabel = PixelNodeFactory.label(
            model.name,
            size: 10,
            color: .white,
            position: CGPoint(x: 0, y: 48),
            z: 20
        )
        bondLabel = PixelNodeFactory.label(
            "",
            size: 9,
            color: NSColor(red: 1.0, green: 0.86, blue: 0.35, alpha: 1),
            position: CGPoint(x: 0, y: 62),
            z: 20
        )
        super.init()

        desk.zPosition = -1
        desk.isHidden = true
        desk.addChild(PixelNodeFactory.rect(
            size: CGSize(width: 46, height: 18),
            color: NSColor(red: 0.28, green: 0.18, blue: 0.10, alpha: 1),
            position: CGPoint(x: 0, y: -28),
            z: 0
        ))
        desk.addChild(PixelNodeFactory.rect(
            size: CGSize(width: 16, height: 10),
            color: NSColor(red: 0.07, green: 0.12, blue: 0.16, alpha: 1),
            position: CGPoint(x: -11, y: -20),
            z: 1
        ))

        addChild(shadow)
        addChild(desk)
        addChild(leftFoot)
        addChild(rightFoot)
        addChild(body)
        addChild(head)
        addChild(hair)
        addChild(accessory)
        addChild(nameLabel)
        addChild(bondLabel)
        addChild(statusBubble)

        update(model: model)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(model: NPCModel) {
        let fallback = NPCVisualState.derive(
            from: model,
            activeSessionCount: currentVisualState?.sessionCount ?? 0,
            dayPhase: currentVisualState?.isNight == true ? .night : .day
        )
        apply(visualState: fallback)
    }

    func apply(visualState: NPCVisualState) {
        currentVisualState = visualState
        nameLabel.text = visualState.name
        bondLabel.text = "Bond \(visualState.bond)  \(formatBits(visualState.totalBits))"

        let palette = palette(for: visualState)
        body.color = palette.body
        hair.color = palette.hair
        accessory.color = palette.accessory
        accessory.isHidden = visualState.bond < 2
        desk.isHidden = !visualState.isWorking

        statusBubble.removeAllChildren()
        if visualState.isWorking {
            let symbol = visualState.loadTier >= 3 ? "!!!" : String(repeating: ">", count: visualState.loadTier)
            statusBubble.addChild(PixelNodeFactory.bubble(text: symbol, position: CGPoint(x: 0, y: 82)))
            startWorkingAnimation(loadTier: visualState.loadTier)
        } else if visualState.activity == .resting {
            statusBubble.addChild(PixelNodeFactory.bubble(text: "zzz", position: CGPoint(x: 0, y: 82)))
            stopWorkingAnimation()
        } else {
            stopWorkingAnimation()
        }
    }

    func showBitsGain(_ delta: Double) {
        let label = SKLabelNode(fontNamed: "Monaco")
        label.text = "+\(formatBits(delta))"
        label.fontSize = 13
        label.fontColor = NSColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
        label.verticalAlignmentMode = .bottom
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: CGFloat.random(in: -10...10), y: 56)
        label.zPosition = 30
        label.setScale(0)
        addChild(label)

        let popIn  = SKAction.scale(to: 1.3, duration: 0.10)
        let settle = SKAction.scale(to: 1.0, duration: 0.08)
        let rise   = SKAction.moveBy(x: 0, y: 38, duration: 0.75)
        let fade   = SKAction.fadeOut(withDuration: 0.75)
        label.run(.sequence([
            .group([popIn]),
            settle,
            .group([rise, fade]),
            .removeFromParent()
        ]))
    }

    func showBondPromotion(level: Int) {
        let ring = SKShapeNode(circleOfRadius: 28)
        ring.strokeColor = NSColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)
        ring.lineWidth = 3
        ring.alpha = 0.95
        ring.zPosition = 70
        addChild(ring)

        let label = PixelNodeFactory.label(
            "Bond \(level)",
            size: 12,
            color: NSColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1),
            position: CGPoint(x: 0, y: 94),
            z: 72
        )
        addChild(label)

        ring.run(.sequence([
            .group([.scale(to: 1.8, duration: 0.55), .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 24, duration: 0.9), .fadeOut(withDuration: 0.9)]),
            .removeFromParent()
        ]))
    }

    func setActive(_ isActive: Bool) {
        if isActive {
            startWorkingAnimation(loadTier: max(currentVisualState?.loadTier ?? 1, 1))
        } else {
            stopWorkingAnimation()
            setScale(1.0)
        }
    }

    private func palette(for state: NPCVisualState) -> (body: NSColor, hair: NSColor, accessory: NSColor) {
        let bodyColors: [NSColor] = [
            NSColor(red: 0.31, green: 0.62, blue: 0.78, alpha: 1),
            NSColor(red: 0.50, green: 0.70, blue: 0.38, alpha: 1),
            NSColor(red: 0.66, green: 0.48, blue: 0.78, alpha: 1),
            NSColor(red: 0.82, green: 0.58, blue: 0.30, alpha: 1),
            NSColor(red: 0.90, green: 0.74, blue: 0.26, alpha: 1)
        ]
        let index = max(0, min(state.bond - 1, bodyColors.count - 1))
        let accessory: NSColor
        switch state.trait {
        case .newAgent:
            accessory = .clear
        case .steady:
            accessory = NSColor(red: 0.95, green: 0.95, blue: 0.78, alpha: 1)
        case .deepThinker:
            accessory = NSColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)
        case .powerUser:
            accessory = NSColor(red: 0.25, green: 0.95, blue: 0.74, alpha: 1)
        }
        return (
            body: bodyColors[index],
            hair: state.isNight ? NSColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1) : NSColor(red: 0.17, green: 0.10, blue: 0.07, alpha: 1),
            accessory: accessory
        )
    }

    private func startWorkingAnimation(loadTier: Int) {
        let duration = max(0.12, 0.34 - Double(loadTier) * 0.06)
        if action(forKey: "workBob") == nil {
            let bob = SKAction.repeatForever(.sequence([
                .moveBy(x: 0, y: 2, duration: duration),
                .moveBy(x: 0, y: -2, duration: duration)
            ]))
            run(bob, withKey: "workBob")
        }
    }

    private func stopWorkingAnimation() {
        removeAction(forKey: "workBob")
    }

    private func formatBits(_ bits: Double) -> String {
        if bits >= 1_000_000 { return String(format: "%.1fM", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.1fk", bits / 1_000) }
        if bits >= 10 { return String(format: "%.0f", bits) }
        return String(format: "%.1f", bits)
    }
}
