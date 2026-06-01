import SpriteKit

@MainActor
final class TiledVillageLayer: SKNode {

    private struct LoadedTileset {
        let firstgid: Int
        let tileset: TiledTileset
        var sheetTexture: SKTexture?
        var tileTextures: [Int: SKTexture] = [:]
        var tileSizes: [Int: CGSize] = [:]
    }

    private let displayTileSize = TileMap.tileSize  // 32 pts per tile

    private(set) var mapCenter: CGPoint = .zero
    private(set) var mapSize: CGSize = .zero

    init(mapURL: URL) {
        super.init()
        zPosition = 4
        guard let raw = try? Data(contentsOf: mapURL),
              let map = try? JSONDecoder().decode(TiledMap.self, from: raw) else { return }
        mapSize = CGSize(width: CGFloat(map.width)  * displayTileSize,
                         height: CGFloat(map.height) * displayTileSize)
        mapCenter = CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
        let mapDir = mapURL.deletingLastPathComponent()
        let tilesets = buildTilesets(refs: map.tilesets, mapDir: mapDir)
        buildLayers(map: map, tilesets: tilesets)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func findMapURL() -> URL? {
        let rel = "tiled/nook-village.tmj"
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["NOOK_TILED_MAP_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        // Bundle first (copied + patched by build phase)
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        // Walk up from bundle and CWD as dev fallback
        let starts = [Bundle.main.bundleURL,
                      URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)]
        for start in starts {
            var dir = start
            for _ in 0..<10 {
                let candidate = dir.appendingPathComponent(rel)
                if fm.fileExists(atPath: candidate.path) { return candidate }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return nil
    }

    // MARK: - Tileset loading

    private func buildTilesets(refs: [TiledTilesetRef], mapDir: URL) -> [LoadedTileset] {
        var result: [LoadedTileset] = []
        for ref in refs {
            let tsjURL = mapDir.appendingPathComponent(ref.source)
            guard let raw = try? Data(contentsOf: tsjURL),
                  let def = try? JSONDecoder().decode(TiledTileset.self, from: raw) else { continue }
            let tsjDir = tsjURL.deletingLastPathComponent()
            var entry = LoadedTileset(firstgid: ref.firstgid, tileset: def)

            if def.columns > 0, let imgRel = def.image {
                let imgURL = resolveImageURL(imgRel, relativeTo: tsjDir)
                if let img = NSImage(contentsOf: imgURL) {
                    let tex = SKTexture(image: img)
                    tex.filteringMode = .nearest
                    entry.sheetTexture = tex
                }
            } else if let tiles = def.tiles {
                for tile in tiles {
                    let imgURL = resolveImageURL(tile.image, relativeTo: tsjDir)
                    guard let img = NSImage(contentsOf: imgURL) else { continue }
                    let tex = SKTexture(image: img)
                    tex.filteringMode = .nearest
                    entry.tileTextures[tile.id] = tex
                    entry.tileSizes[tile.id] = CGSize(width: CGFloat(tile.imagewidth),
                                                      height: CGFloat(tile.imageheight))
                }
            }
            result.append(entry)
        }
        return result.sorted { $0.firstgid < $1.firstgid }
    }

    private func resolveImageURL(_ path: String, relativeTo base: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return base.appendingPathComponent(path)
    }

    // MARK: - Layer rendering

    private func buildLayers(map: TiledMap, tilesets: [LoadedTileset]) {
        let H = map.height
        for (idx, layer) in map.layers.enumerated() {
            guard layer.type == "tilelayer", layer.visible,
                  let data = layer.data,
                  let W = layer.width, let LH = layer.height else { continue }
            let baseZ = CGFloat(idx) * 20
            for row in 0..<LH {
                for col in 0..<W {
                    let gid = data[row * W + col]
                    guard gid > 0 else { continue }
                    guard let (entry, localId) = resolve(gid: gid, in: tilesets) else { continue }
                    let skX = CGFloat(col) * displayTileSize
                    let skY = CGFloat(H - 1 - row) * displayTileSize
                    if entry.tileset.columns > 0 {
                        addGridSprite(entry: entry, localId: localId, skX: skX, skY: skY, baseZ: baseZ)
                    } else {
                        addCollectionSprite(entry: entry, localId: localId, skX: skX, skY: skY, baseZ: baseZ)
                    }
                }
            }
        }
    }

    private func resolve(gid: Int, in tilesets: [LoadedTileset]) -> (LoadedTileset, Int)? {
        var best: LoadedTileset? = nil
        for entry in tilesets {
            guard entry.firstgid <= gid else { continue }
            if best == nil || entry.firstgid > best!.firstgid { best = entry }
        }
        guard let resolved = best else { return nil }
        return (resolved, gid - resolved.firstgid)
    }

    // MARK: - Sprite factories

    private func addGridSprite(entry: LoadedTileset, localId: Int, skX: CGFloat, skY: CGFloat, baseZ: CGFloat) {
        guard let sheet = entry.sheetTexture,
              let imgW = entry.tileset.imagewidth,
              let imgH = entry.tileset.imageheight else { return }
        let cols = entry.tileset.columns
        let tw = entry.tileset.tilewidth
        let th = entry.tileset.tileheight
        let tileCol = localId % cols
        let tileRow = localId / cols
        // UV: SpriteKit Y origin is bottom, so flip V
        let u  = CGFloat(tileCol * tw) / CGFloat(imgW)
        let v  = 1.0 - CGFloat((tileRow + 1) * th) / CGFloat(imgH)
        let uw = CGFloat(tw) / CGFloat(imgW)
        let uh = CGFloat(th) / CGFloat(imgH)
        let tex = SKTexture(rect: CGRect(x: u, y: v, width: uw, height: uh), in: sheet)
        tex.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: tex, size: CGSize(width: displayTileSize,
                                                             height: displayTileSize))
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: skX, y: skY)
        sprite.zPosition = baseZ
        addChild(sprite)
    }

    private func addCollectionSprite(entry: LoadedTileset, localId: Int, skX: CGFloat, skY: CGFloat, baseZ: CGFloat) {
        guard let tex = entry.tileTextures[localId],
              let native = entry.tileSizes[localId] else { return }
        let sprite = SKSpriteNode(texture: tex,
                                  size: CGSize(width: native.width * 2, height: native.height * 2))
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: skX, y: skY)
        // Y-sort: lower screen position = higher z (renders in front)
        sprite.zPosition = baseZ + (2000.0 - skY) * 0.001
        addChild(sprite)
    }
}
