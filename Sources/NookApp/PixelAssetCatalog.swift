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

        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("GeneratedAssets.local/Maygetsu", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("Maygetsu", isDirectory: true))
        }

        let cwd = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        candidates.append(cwd.appendingPathComponent("NookApp/GeneratedAssets.local/Maygetsu", isDirectory: true))
        candidates.append(cwd.appendingPathComponent("GeneratedAssets.local/Maygetsu", isDirectory: true))

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
