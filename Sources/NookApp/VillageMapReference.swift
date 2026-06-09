// Static reference for nook-village.tmj (24×24 tiles, 32 px/tile)
// All positions in SpriteKit tile coordinates:
//   tileX: 0 (left) → 23 (right)
//   tileY: 0 (bottom) → 23 (top)    ← Y is flipped vs Tiled rows
//
// Derivation: tileY = mapHeight - 1 - tiledRow
//
// Cross-path geometry:
//   Vertical path:   tileX 10–13  (center axis = 11.5)  — runs full map height
//   Horizontal path: tileY 10–13  (center axis = 11.5)  — runs full map width

enum VillageMapReference {

    // MARK: - Path geometry

    static let verticalPathX:   ClosedRange<Int> = 10...13   // center axis 11.5
    static let horizontalPathY: ClosedRange<Int> = 10...13   // center axis 11.5

    // MARK: - Intersection landmarks

    // fountain03 — center anchor of the animated fountain sprite
    static let fountain = TilePosition(tileX: 11, tileY: 11)

    // bench_whiteF — flanking the intersection from above (tileY=14)
    static let benchNorthWest = TilePosition(tileX:  7, tileY: 14)
    static let benchNorthEast = TilePosition(tileX: 15, tileY: 14)

    // smalllamp — lampposts above and below the intersection
    static let lampNorthWest = TilePosition(tileX:  9, tileY: 14)
    static let lampNorthEast = TilePosition(tileX: 14, tileY: 14)
    static let lampSouthWest = TilePosition(tileX:  9, tileY:  9)
    static let lampSouthEast = TilePosition(tileX: 14, tileY:  9)

    // flowerbed_Horizontal — at the southern path entrance (tileY=9)
    static let flowerBedSouthWest = TilePosition(tileX:  7, tileY:  9)
    static let flowerBedSouthEast = TilePosition(tileX: 15, tileY:  9)

    // MARK: - Nature elements

    // tileY is the anchor tile; multi-tile props visually extend upward/rightward
    static let bushNorthWest  = TilePosition(tileX:  6, tileY: 16)  // bush3x4
    static let bushNorthEast  = TilePosition(tileX: 17, tileY: 15)  // bush2x2
    static let treeSouthWest1 = TilePosition(tileX:  4, tileY:  4)  // tree
    static let treeSouthWest2 = TilePosition(tileX:  7, tileY:  2)  // bush2x2
    static let treeSouthEast1 = TilePosition(tileX: 19, tileY:  5)  // tree
    static let treeSouthEast2 = TilePosition(tileX: 15, tileY:  4)  // pinetree
    static let treeSouthEast3 = TilePosition(tileX: 20, tileY:  1)  // bush2x2
    static let treeBottomLeft = TilePosition(tileX:  1, tileY:  0)  // pinetree

    // MARK: - Preferred desk positions

    // On the horizontal path (tileY=11), symmetric about the vertical-path center
    // axis (tileX=11.5).  Each pair is equidistant from the axis; pairs are spaced
    // 3 tiles apart so greedy-2 spacing never eliminates any of them.
    //
    //  left-3   left-2   left-1   [path 10-13]   right-1  right-2  right-3
    //    2        5         8     ~~11.5~~          15       18       21
    static let preferredDeskTiles: [TilePosition] = [
        TilePosition(tileX:  8, tileY: 11),   // left-1:  3.5 tiles from axis
        TilePosition(tileX: 15, tileY: 11),   // right-1: 3.5 tiles from axis
        TilePosition(tileX:  5, tileY: 11),   // left-2:  6.5 tiles from axis
        TilePosition(tileX: 18, tileY: 11),   // right-2: 6.5 tiles from axis
        TilePosition(tileX:  2, tileY: 11),   // left-3:  9.5 tiles from axis
        TilePosition(tileX: 21, tileY: 11),   // right-3: 9.5 tiles from axis
    ]
}
