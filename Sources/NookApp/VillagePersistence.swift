import Foundation

struct TilePosition: Codable {
    var tileX: Int
    var tileY: Int
}

struct VillageState: Codable {
    var npcPositions: [String: TilePosition]
    var revealedZones: [String]
    var lastSaved: Date

    static var empty: VillageState {
        VillageState(npcPositions: [:], revealedZones: [], lastSaved: Date())
    }
}

@MainActor
final class VillagePersistence {
    static let shared = VillagePersistence()

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/village.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectory()
    }

    func load() -> VillageState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(VillageState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: VillageState) {
        guard let data = try? encoder.encode(state) else { return }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try data.write(to: tmp)
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private func ensureDirectory() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
