import SpriteKit
import AppKit

@MainActor
final class VillageCamera: SKCameraNode {
    private weak var trackedView: SKView?
    private var panRecognizer: NSPanGestureRecognizer?
    private var magnifyRecognizer: NSMagnificationGestureRecognizer?

    // Zoom limits
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 5.0

    func attach(to view: SKView) {
        trackedView = view
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
        panRecognizer = pan

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        view.addGestureRecognizer(magnify)
        magnifyRecognizer = magnify
    }

    func detach() {
        if let pan = panRecognizer, let view = trackedView {
            view.removeGestureRecognizer(pan)
        }
        if let magnify = magnifyRecognizer, let view = trackedView {
            view.removeGestureRecognizer(magnify)
        }
        panRecognizer = nil
        magnifyRecognizer = nil
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

    @objc private func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
        guard recognizer.state == .changed || recognizer.state == .ended else { return }
        // magnification = 0 → no change, positive = zoom in, negative = zoom out
        // Camera scale: smaller = zoomed in, larger = zoomed out → invert
        let newScale = (xScale / (1 + recognizer.magnification)).clamped(to: minScale...maxScale)
        setScale(newScale)
        recognizer.magnification = 0
        clampPosition()
    }

    // Fallback for non-trackpad scroll (mouse wheel)
    func handleScroll(deltaY: CGFloat) {
        let factor = 1.0 + deltaY * 0.05
        let newScale = (xScale * factor).clamped(to: minScale...maxScale)
        setScale(newScale)
        clampPosition()
    }

    func clampPosition() {
        guard let view = trackedView, view.bounds.width > 0 else { return }
        let halfW = view.bounds.width  * xScale / 2
        let halfH = view.bounds.height * yScale / 2
        let mapW = TileMap.mapWidth
        let mapH = TileMap.mapHeight
        if halfW >= mapW / 2 {
            position.x = mapW / 2
        } else {
            position.x = position.x.clamped(to: halfW...(mapW - halfW))
        }
        if halfH >= mapH / 2 {
            position.y = mapH / 2
        } else {
            position.y = position.y.clamped(to: halfH...(mapH - halfH))
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
