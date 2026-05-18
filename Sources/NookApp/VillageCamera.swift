import SpriteKit
import AppKit

@MainActor
final class VillageCamera: SKCameraNode {
    private weak var trackedView: SKView?
    private var panRecognizer: NSPanGestureRecognizer?

    // Zoom limits
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 3.0

    func attach(to view: SKView) {
        trackedView = view
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
        panRecognizer = pan
    }

    func detach() {
        if let pan = panRecognizer, let view = trackedView {
            view.removeGestureRecognizer(pan)
        }
        panRecognizer = nil
        trackedView = nil
    }

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard let _ = self.scene else { return }
        let translation = recognizer.translation(in: recognizer.view)
        let dx = -translation.x * xScale
        // macOS NSView Y+ is up; drag-up → translation.y+ → camera moves down in SpriteKit → negate
        let dy = -translation.y * yScale
        position.x += dx
        position.y += dy
        recognizer.setTranslation(.zero, in: recognizer.view)
        clampPosition()
    }

    // Called from the scene's scrollWheel override
    func handleScroll(deltaY: CGFloat) {
        let factor = 1.0 + deltaY * 0.05
        let newScale = (xScale * factor).clamped(to: minScale...maxScale)
        setScale(newScale)
        clampPosition()
    }

    private func clampPosition() {
        guard let view = self.scene?.view else { return }
        let halfW = view.frame.width  * xScale / 2
        let halfH = view.frame.height * yScale / 2
        let mapW = TileMap.mapWidth
        let mapH = TileMap.mapHeight
        position.x = position.x.clamped(to: halfW...(mapW - halfW))
        position.y = position.y.clamped(to: halfH...(mapH - halfH))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
