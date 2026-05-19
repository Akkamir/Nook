import Foundation
import SpriteKit

enum PixelAssetSection {
    case terrain
    case props
}

struct PixelAssetEntry: Codable, Equatable {
    let role: String
    let path: String
    let kind: String
    let tileWidth: Int
    let tileHeight: Int
}

struct PixelAssetManifest: Codable, Equatable {
    let version: Int
    let pack: String
    let tileSize: Int
    let terrain: [PixelAssetEntry]
    let props: [PixelAssetEntry]
    let characters: [PixelAssetEntry]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        pack = try c.decode(String.self, forKey: .pack)
        tileSize = try c.decode(Int.self, forKey: .tileSize)
        terrain = try c.decode([PixelAssetEntry].self, forKey: .terrain)
        props = try c.decode([PixelAssetEntry].self, forKey: .props)
        characters = (try? c.decode([PixelAssetEntry].self, forKey: .characters)) ?? []
    }
}

final class PixelAssetCatalog {
    enum CatalogError: Error {
        case manifestMissing(URL)
    }

    let rootURL: URL
    let manifest: PixelAssetManifest

    private var textureCache: [String: SKTexture] = [:]

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        let manifestURL = rootURL.appendingPathComponent("maygetsu-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CatalogError.manifestMissing(manifestURL)
        }
        let data = try Data(contentsOf: manifestURL)
        manifest = try JSONDecoder().decode(PixelAssetManifest.self, from: data)
    }

    static func loadMaygetsu() -> PixelAssetCatalog? {
        for candidate in maygetsuRootCandidates() {
            if let catalog = try? PixelAssetCatalog(rootURL: candidate) {
                return catalog
            }
        }
        return nil
    }

    static func maygetsuRootCandidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        bundle: Bundle = .main
    ) -> [URL] {
        var candidates: [URL] = []

        if let override = environment["NOOK_MAYGETSU_ASSET_ROOT"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        // Bundled (only present when explicitly copied into the app bundle)
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("GeneratedAssets.local/Maygetsu", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("Maygetsu", isDirectory: true))
        }

        // Walk up from bundle path — finds the repo root even when Xcode sets a
        // different CWD (e.g. DerivedData). Stops after 10 levels.
        let relPath = "NookApp/GeneratedAssets.local/Maygetsu"
        var walkers: [URL] = []
        if let bundleURL = bundle.bundleURL.standardizedFileURL as URL? {
            walkers.append(bundleURL)
        }
        let cwd = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        walkers.append(cwd)

        for start in walkers {
            var dir = start
            for _ in 0..<10 {
                candidates.append(dir.appendingPathComponent(relPath, isDirectory: true))
                candidates.append(dir.appendingPathComponent("GeneratedAssets.local/Maygetsu", isDirectory: true))
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }

        return unique(candidates)
    }

    func entry(for role: String, in section: PixelAssetSection) -> PixelAssetEntry? {
        let entries: [PixelAssetEntry]
        switch section {
        case .terrain:
            entries = manifest.terrain
        case .props:
            entries = manifest.props
        }
        return entries.first { $0.role == role }
    }

    func fileURL(for entry: PixelAssetEntry) -> URL {
        rootURL.appendingPathComponent(entry.path)
    }

    func texture(for entry: PixelAssetEntry) -> SKTexture? {
        if let cached = textureCache[entry.path] {
            return cached
        }
        let url = fileURL(for: entry)
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        textureCache[entry.path] = texture
        return texture
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            result.append(url)
        }
        return result
    }
}
