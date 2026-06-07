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

    static func workBubble(loadTier: Int, position: CGPoint) -> SKNode {
        let root = SKNode()
        root.position = position
        root.zPosition = 80

        let background = rect(
            size: CGSize(width: 34, height: 20),
            color: NSColor.black.withAlphaComponent(0.82),
            z: 0
        )
        root.addChild(background)

        let count = max(1, min(loadTier, 3))
        let startX = CGFloat(1 - count) * 4
        for index in 0..<count {
            let height = CGFloat(5 + index * 2)
            let bar = rect(
                size: CGSize(width: 4, height: height),
                color: NSColor(red: 0.42, green: 0.94, blue: 1.0, alpha: 1),
                position: CGPoint(x: startX + CGFloat(index) * 8, y: 0),
                z: 1
            )
            bar.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.45, duration: 0.28 + Double(index) * 0.04),
                .fadeAlpha(to: 1.0, duration: 0.28)
            ])))
            root.addChild(bar)
        }

        return root
    }
}
