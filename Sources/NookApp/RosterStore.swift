import Foundation

struct RosterStore {
    let url: URL
    let catalog: NPCCatalog
    private let fm: FileManager

    init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/roster.json"),
        catalog: NPCCatalog = .standard,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.catalog = catalog
        self.fm = fileManager
    }

    func exists() -> Bool {
        fm.fileExists(atPath: url.path)
    }

    func load() throws -> NPCRoster {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var roster = try decoder.decode(NPCRoster.self, from: data)
        roster.mergeMissingCatalogEntries(from: catalog)
        return roster
    }

    func loadOrLockedRoster() -> NPCRoster {
        (try? load()) ?? .emptyLocked(catalog: catalog)
    }

    func save(_ roster: NPCRoster) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(roster)
        try data.write(to: url, options: .atomic)
    }

    func assign(projectPath: String, toCatalogId catalogId: String, in roster: inout NPCRoster) throws {
        guard let entry = roster.entry(catalogId: catalogId), entry.isUnlocked else { return }
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        guard !roster.isProjectAssigned(projectURL.path, excludingCatalogId: catalogId) else { return }
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let configURL = projectURL.appendingPathComponent(".pixelvillage")
        let data = try JSONSerialization.data(
            withJSONObject: ["agent": entry.name],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
        roster.addAssignedProject(projectURL.path, toCatalogId: catalogId)
        try save(roster)
    }

    func unassign(projectPath: String, fromCatalogId catalogId: String, in roster: inout NPCRoster) throws {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let configURL = projectURL.appendingPathComponent(".pixelvillage")
        if fm.fileExists(atPath: configURL.path) {
            try fm.removeItem(at: configURL)
        }
        roster.removeAssignedProject(projectURL.path, fromCatalogId: catalogId)
        try save(roster)
    }

    func applyAssignments(
        forCatalogId catalogId: String,
        newProjectPaths: [String],
        roster: inout NPCRoster
    ) throws {
        let current = Set(roster.entry(catalogId: catalogId)?.assignedProjects ?? [])
        let next = Set(newProjectPaths)
        for path in current.subtracting(next) {
            try unassign(projectPath: path, fromCatalogId: catalogId, in: &roster)
        }
        for path in next.subtracting(current) {
            try assign(projectPath: path, toCatalogId: catalogId, in: &roster)
        }
    }
}
