import SpriteKit

@MainActor
final class NPCSprite: SKNode {

    private static let catalog: PixelAssetCatalog? = PixelAssetCatalog.loadMaygetsu()

    private let character: SKSpriteNode
    private let statusBubble = SKNode()
    private let nameLabel: SKLabelNode
    private let bondLabel: SKLabelNode
    private var currentVisualState: NPCVisualState?

    // Native 16×32 px → displayed at 2× = 32×64 pts
    private static let frameW: Int    = 16
    private static let frameH: Int    = 32
    private static let scale: CGFloat = 2.0
    private static let charW: CGFloat = CGFloat(frameW) * scale   // 32
    private static let charH: CGFloat = CGFloat(frameH) * scale   // 64

    // [direction][frame] — 3 dirs (0=down, 1=up, 2=right) × 7 frames
    // frames 0-2: walk  |  frames 3-4: typing  |  frames 5-6: reading
    private var paFrames: [[SKTexture]] = []
    private var isWalking = false
    private var lastWalkDirection: Int = 0

    private let charIndex: Int

    /// Stable across launches: String.hashValue is seeded per-process, so it
    /// would re-roll the character every restart. FNV-1a over the id keeps the
    /// same sprite for the same agent forever.
    nonisolated static func charIndex(for id: String, count: Int = 6) -> Int {
        var hash: UInt64 = 1469598103934665603  // FNV-1a offset basis
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211         // FNV-1a prime
        }
        return Int(hash % UInt64(count))
    }

    init(model: NPCModel) {
        charIndex = Self.charIndex(for: model.id)

        character = SKSpriteNode()
        character.size = CGSize(width: Self.charW, height: Self.charH)
        character.anchorPoint = CGPoint(x: 0.5, y: 0)
        character.zPosition = 2

        let labelBaseY = Self.charH + 8
        nameLabel = PixelNodeFactory.label(
            model.name,
            size: 10,
            color: .white,
            position: CGPoint(x: 0, y: labelBaseY),
            z: 20
        )
        bondLabel = PixelNodeFactory.label(
            "",
            size: 9,
            color: NSColor(red: 0.84, green: 0.96, blue: 1.0, alpha: 1),
            position: CGPoint(x: 0, y: labelBaseY + 14),
            z: 20
        )

        super.init()

        addChild(character)
        addChild(nameLabel)
        addChild(bondLabel)
        addChild(statusBubble)

        loadFrames()
        showIdleFrame(direction: 0)
        update(model: model)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Frame loading

    private func loadFrames() {
        guard let catalog = Self.catalog else { applyFallbackColor(); return }
        let charURL = catalog.rootURL.appendingPathComponent("pixel-agents/char_\(charIndex).png")
        guard let image = NSImage(contentsOf: charURL) else { applyFallbackColor(); return }

        let sheet = SKTexture(image: image)
        sheet.filteringMode = .nearest

        // Sheet: 112×96 — 7 cols × 16px, 3 rows × 32px
        // Row order in image (top→bottom): down, up, right
        // SpriteKit UV: Y=0 at bottom → row 0(down) has highest V
        let fw = CGFloat(Self.frameW) / 112.0
        let fh = CGFloat(Self.frameH) / 96.0

        paFrames = (0..<3).map { dir in
            let v = CGFloat(2 - dir) * fh
            return (0..<7).map { i in
                let tex = SKTexture(
                    rect: CGRect(x: CGFloat(i) * fw, y: v, width: fw, height: fh),
                    in: sheet
                )
                tex.filteringMode = .nearest
                return tex
            }
        }
    }

    private func applyFallbackColor() {
        character.color = NSColor(red: 0.31, green: 0.62, blue: 0.78, alpha: 1)
        character.colorBlendFactor = 1
    }

    // MARK: - Animation helpers

    private func showIdleFrame(direction: Int = 0) {
        character.removeAction(forKey: "charAnim")
        guard !paFrames.isEmpty else { return }
        let (sheetDir, flip) = sheetDirAndFlip(for: direction)
        character.xScale = flip ? -1.0 : 1.0
        character.texture = paFrames[sheetDir][0]
    }

    private func startWalkAnimation(direction: Int) {
        guard !paFrames.isEmpty else { return }
        let (sheetDir, flip) = sheetDirAndFlip(for: direction)
        character.xScale = flip ? -1.0 : 1.0
        character.removeAction(forKey: "charAnim")
        let f = paFrames[sheetDir]
        character.run(.repeatForever(.animate(with: [f[0], f[1], f[2], f[1]], timePerFrame: 0.15)),
                      withKey: "charAnim")
    }

    private func sheetDirAndFlip(for direction: Int) -> (Int, Bool) {
        switch direction {
        case 1:  return (2, true)   // left = right flipped
        case 2:  return (2, false)  // right
        case 3:  return (1, false)  // up
        default: return (0, false)  // down
        }
    }

    func startWalking(direction: Int) {
        isWalking = true
        lastWalkDirection = direction
        startWalkAnimation(direction: direction)
    }

    func stopWalking() {
        isWalking = false
        showIdleFrame(direction: lastWalkDirection)
    }

    private func startTypingAnimation(loadTier: Int = 1) {
        guard !paFrames.isEmpty else { return }
        character.xScale = 1.0
        character.removeAction(forKey: "charAnim")
        let f = paFrames[0]
        // Frames 3-4 are the seated typing pose (feet together): only the arms
        // move, so this reads as work rather than walking.
        let timePerFrame = max(0.10, 0.24 - Double(loadTier) * 0.03)
        character.run(.repeatForever(.animate(with: [f[3], f[4]], timePerFrame: timePerFrame)),
                      withKey: "charAnim")
    }

    // MARK: - Public API

    func update(model: NPCModel) {
        let state = NPCVisualState.derive(
            from: model,
            activeSessionCount: currentVisualState?.sessionCount ?? 0,
            dayPhase: currentVisualState?.isNight == true ? .night : .day
        )
        apply(visualState: state)
    }

    func apply(visualState: NPCVisualState) {
        currentVisualState = visualState
        nameLabel.text = visualState.name
        var bondText = "Bond \(visualState.bond)  \(formatBits(visualState.availableBits))"
        if visualState.bitMultiplier > 1.0 {
            bondText += "  \(formatMultiplier(visualState.bitMultiplier))x"
        }
        bondLabel.text = bondText

        statusBubble.removeAllChildren()
        if visualState.isWorking {
            statusBubble.addChild(PixelNodeFactory.workBubble(
                loadTier: visualState.loadTier,
                position: CGPoint(x: 0, y: Self.charH + 42)
            ))
            startWorkingAnimation(loadTier: visualState.loadTier)
        } else if visualState.activity == .resting {
            statusBubble.addChild(PixelNodeFactory.bubble(
                text: "zzz",
                position: CGPoint(x: 0, y: Self.charH + 42)
            ))
            stopWorkingAnimation()
        } else {
            stopWorkingAnimation()
        }
    }

    func showBitsGain(_ delta: Double) {
        let pulse = SKShapeNode(circleOfRadius: 24)
        pulse.strokeColor = NSColor(red: 0.38, green: 1.0, blue: 0.72, alpha: 0.9)
        pulse.lineWidth = 2
        pulse.zPosition = 25
        pulse.alpha = 0.7
        addChild(pulse)
        pulse.run(.sequence([
            .group([.scale(to: 1.7, duration: 0.35), .fadeOut(withDuration: 0.35)]),
            .removeFromParent()
        ]))

        let root = SKNode()
        root.position = CGPoint(x: CGFloat.random(in: -10...10), y: Self.charH - 8)
        root.zPosition = 30
        root.setScale(0)
        addChild(root)

        let text = "+\(formatBits(delta))"
        for offset in [
            CGPoint(x: -1, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0, y: -1),
            CGPoint(x: 0, y: 1)
        ] {
            let outline = SKLabelNode(fontNamed: "Monaco")
            outline.text = text
            outline.fontSize = 20
            outline.fontColor = NSColor.black.withAlphaComponent(0.88)
            outline.verticalAlignmentMode = .bottom
            outline.horizontalAlignmentMode = .center
            outline.position = offset
            outline.zPosition = 0
            root.addChild(outline)
        }

        let label = SKLabelNode(fontNamed: "Monaco")
        label.text = text
        label.fontSize = 20
        label.fontColor = NSColor(red: 0.38, green: 1.0, blue: 0.72, alpha: 1)
        label.verticalAlignmentMode = .bottom
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        root.addChild(label)

        root.run(.sequence([
            .group([.scale(to: 1.45, duration: 0.10)]),
            .scale(to: 1.0, duration: 0.08),
            .group([.moveBy(x: 0, y: 46, duration: 0.9), .fadeOut(withDuration: 0.9)]),
            .removeFromParent()
        ]))
    }

    func showSpeech(_ text: String) {
        // One bubble at a time.
        childNode(withName: "speech")?.removeFromParent()

        // Lines are kept short at the source; this is only a last-resort cap so a
        // rogue long line can't grow an unbounded bubble.
        let display = text.count > 140 ? String(text.prefix(139)) + "…" : text

        let label = SKLabelNode(fontNamed: "Monaco")
        label.text = display
        label.fontSize = 11
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.preferredMaxLayoutWidth = 200
        label.numberOfLines = 3
        label.lineBreakMode = .byTruncatingTail

        let padding: CGFloat = 8
        let textSize = label.frame.size
        let bubbleW = min(max(textSize.width + padding * 2, 40), 216)
        let bubbleH = textSize.height + padding * 2

        let bubble = SKShapeNode(rectOf: CGSize(width: bubbleW, height: bubbleH), cornerRadius: 6)
        bubble.name = "speech"
        bubble.fillColor = NSColor(white: 0.97, alpha: 0.96)
        bubble.strokeColor = NSColor(white: 0.2, alpha: 0.9)
        bubble.lineWidth = 1
        bubble.position = CGPoint(x: 0, y: Self.charH + 30)
        bubble.zPosition = 40
        bubble.addChild(label)

        // Little tail.
        let tail = SKShapeNode(rectOf: CGSize(width: 6, height: 6))
        tail.fillColor = bubble.fillColor
        tail.strokeColor = bubble.strokeColor
        tail.lineWidth = 1
        tail.zRotation = .pi / 4
        tail.position = CGPoint(x: 0, y: -bubbleH / 2)
        bubble.addChild(tail)

        bubble.alpha = 0
        bubble.setScale(0.9)
        addChild(bubble)

        let hold = max(2.5, min(8.0, Double(display.count) * 0.07))
        bubble.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.0, duration: 0.12)]),
            .wait(forDuration: hold),
            .group([.fadeOut(withDuration: 0.3)]),
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
            position: CGPoint(x: 0, y: Self.charH + 30),
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
        }
    }

    /// Restores the typing pose after a positional move (walk-to-desk or the
    /// deskless back-and-forth) interrupted it with walk frames.
    func resumeWorkPose() {
        startWorkingAnimation(loadTier: max(currentVisualState?.loadTier ?? 1, 1))
    }

    // MARK: - Private

    private func startWorkingAnimation(loadTier: Int) {
        isWalking = false
        startTypingAnimation(loadTier: loadTier)
        removeAction(forKey: "workMicro")
        let lean = SKAction.scaleX(to: 1.04, y: 0.98, duration: 0.45)
        let settle = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.35)
        let pause = SKAction.wait(forDuration: 1.2, withRange: 0.8)
        run(.repeatForever(.sequence([pause, lean, settle])), withKey: "workMicro")
    }

    private func stopWorkingAnimation() {
        removeAction(forKey: "workMicro")
        setScale(1.0)
        if !isWalking {
            showIdleFrame(direction: lastWalkDirection)
        }
    }

    private func formatBits(_ bits: Double) -> String {
        if bits >= 1_000_000 { return String(format: "%.1fM", bits / 1_000_000) }
        if bits >= 1_000    { return String(format: "%.1fk", bits / 1_000) }
        if bits >= 10        { return String(format: "%.0f", bits) }
        return String(format: "%.1f", bits)
    }

    private func formatMultiplier(_ value: Double) -> String {
        // Drop the trailing ".00" for whole multipliers (e.g. 2x not 2.00x).
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
