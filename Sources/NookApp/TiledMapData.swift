import Foundation

struct TiledMap: Decodable {
    let width: Int
    let height: Int
    let tilewidth: Int
    let tileheight: Int
    let layers: [TiledLayer]
    let tilesets: [TiledTilesetRef]
}

struct TiledTilesetRef: Decodable {
    let firstgid: Int
    let source: String
}

struct TiledLayer: Decodable {
    let id: Int
    let name: String
    let type: String
    let data: [Int]?
    let width: Int?
    let height: Int?
    let visible: Bool
    let opacity: Double
}

struct TiledTileset: Decodable {
    let name: String
    let tilewidth: Int
    let tileheight: Int
    let tilecount: Int
    let columns: Int
    // Grid tilesets:
    let image: String?
    let imagewidth: Int?
    let imageheight: Int?
    // Image-collection tilesets:
    let tiles: [TiledTileInfo]?
}

struct TiledTileInfo: Decodable {
    let id: Int
    let image: String
    let imagewidth: Int
    let imageheight: Int
}
