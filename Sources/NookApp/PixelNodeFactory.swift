import SpriteKit

@MainActor
enum PixelNodeFactory {
    static func rect(
        size: CGSize,
        color: NSColor,
        position: CGPoint = .zero,
        z: CGFloat = 0
    ) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: size)
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.position = position
        node.zPosition = z
        node.colorBlendFactor = 1
        return node
    }

    static func label(
        _ text: String,
        size: CGFloat,
        color: NSColor,
        position: CGPoint,
        z: CGFloat = 0
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "Monaco")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = position
        label.zPosition = z
        return label
    }

    static func bubble(text: String, position: CGPoint) -> SKNode {
        let root = SKNode()
        root.position = position
        root.zPosition = 80
        let background = rect(
            size: CGSize(width: 34, height: 20),
            color: NSColor.black.withAlphaComponent(0.78),
            z: 0
        )
        let label = label(text, size: 11, color: .white, position: CGPoint(x: 0, y: 1), z: 1)
        root.addChild(background)
        root.addChild(label)
        return root
    }
}
