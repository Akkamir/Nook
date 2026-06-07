import CoreGraphics

struct DeskLayout {
    let deskNodeYOffset: CGFloat
    let deskTopY: CGFloat
    let deskSurfaceY: CGFloat
    let pcPosition: CGPoint
    let pcTopY: CGFloat

    static func front(
        tileSize: CGFloat,
        displayScale: CGFloat,
        characterHeight: CGFloat,
        deskPixelSize: CGSize,
        pcPixelSize: CGSize
    ) -> DeskLayout {
        let deskHeight = deskPixelSize.height * displayScale
        let pcHeight = pcPixelSize.height
        let deskTopY = characterHeight * 0.28125
        let deskSurfaceY = deskTopY
        let deskSurfaceFromBottom = deskHeight - tileSize * 0.75
        let deskNodeYOffset = deskTopY - deskHeight
        let pcY = deskSurfaceFromBottom - pcHeight * 0.375
        let pcTopY = deskNodeYOffset + pcY + pcHeight
        return DeskLayout(
            deskNodeYOffset: deskNodeYOffset,
            deskTopY: deskTopY,
            deskSurfaceY: deskSurfaceY,
            pcPosition: CGPoint(x: 0, y: pcY),
            pcTopY: pcTopY
        )
    }
}
