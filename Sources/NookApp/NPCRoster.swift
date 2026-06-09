import Foundation

struct RosterEntry: Codable, Equatable, Identifiable {
    var id: String { catalogId }
    let catalogId: String
    var name: String
    var unlockedAt: Date?
    var assignedProjects: [String]

    var isUnlocked: Bool { unlockedAt != nil }
}

struct NPCRoster: Codable, Equatable {
    var version: Int
    var entries: [RosterEntry]

    static func initial(
        catalog: NPCCatalog,
        starterName: String,
        assignedProjects: [String],
        now: Date
    ) -> NPCRoster {
        NPCRoster(
            version: 1,
            entries: catalog.entries.map { entry in
                RosterEntry(
                    catalogId: entry.catalogId,
                    name: entry.catalogId == "starter" ? starterName : (entry.defaultName ?? entry.catalogId),
                    unlockedAt: entry.catalogId == "starter" ? now : nil,
                    assignedProjects: entry.catalogId == "starter" ? Self.uniqueSorted(assignedProjects) : []
                )
            }
        )
    }

    static func emptyLocked(catalog: NPCCatalog) -> NPCRoster {
        NPCRoster(
            version: 1,
            entries: catalog.entries.map { entry in
                RosterEntry(
                    catalogId: entry.catalogId,
                    name: entry.defaultName ?? entry.catalogId,
                    unlockedAt: nil,
                    assignedProjects: []
                )
            }
        )
    }

    var needsOnboarding: Bool {
        entries.allSatisfy { $0.unlockedAt == nil }
    }

    func entry(catalogId: String) -> RosterEntry? {
        entries.first { $0.catalogId == catalogId }
    }

    func entry(forAgentName agentName: String) -> RosterEntry? {
        entries.first { $0.name == agentName }
    }

    func isProjectAssigned(_ path: String, excludingCatalogId catalogId: String? = nil) -> Bool {
        entries.contains { entry in
            if let catalogId, entry.catalogId == catalogId { return false }
            return entry.assignedProjects.contains(path)
        }
    }

    func availableProjects(from projects: [DiscoveredProject], forCatalogId catalogId: String) -> [DiscoveredProject] {
        projects.filter { project in
            !isProjectAssigned(project.path, excludingCatalogId: catalogId)
        }
    }

    mutating func rename(catalogId: String, to name: String) {
        guard let index = entries.firstIndex(where: { $0.catalogId == catalogId }) else { return }
        entries[index].name = name
    }

    mutating func setAssignedProjects(_ paths: [String], forCatalogId catalogId: String) {
        guard let index = entries.firstIndex(where: { $0.catalogId == catalogId }) else { return }
        entries[index].assignedProjects = Self.uniqueSorted(paths)
    }

    mutating func addAssignedProject(_ path: String, toCatalogId catalogId: String) {
        guard let index = entries.firstIndex(where: { $0.catalogId == catalogId }) else { return }
        entries[index].assignedProjects = Self.uniqueSorted(entries[index].assignedProjects + [path])
    }

    mutating func removeAssignedProject(_ path: String, fromCatalogId catalogId: String) {
        guard let index = entries.firstIndex(where: { $0.catalogId == catalogId }) else { return }
        entries[index].assignedProjects.removeAll { $0 == path }
    }

    mutating func unlockEligibleEntries(
        catalog: NPCCatalog,
        maxBond: Int,
        totalSpentBits: Double,
        totalVillageBits: Double,
        now: Date
    ) -> [String] {
        var unlocked: [String] = []
        for catalogEntry in catalog.entries {
            guard let index = entries.firstIndex(where: { $0.catalogId == catalogEntry.catalogId }),
                  entries[index].unlockedAt == nil,
                  catalogEntry.unlockCondition.isMet(
                    maxBond: maxBond,
                    totalSpentBits: totalSpentBits,
                    totalVillageBits: totalVillageBits
                  )
            else { continue }
            entries[index].unlockedAt = now
            unlocked.append(catalogEntry.catalogId)
        }
        return unlocked
    }

    mutating func relockIneligibleUnassignedEntries(
        catalog: NPCCatalog,
        maxBond: Int,
        totalSpentBits: Double,
        totalVillageBits: Double
    ) -> Bool {
        var changed = false
        for catalogEntry in catalog.entries {
            guard catalogEntry.unlockCondition != .free,
                  let index = entries.firstIndex(where: { $0.catalogId == catalogEntry.catalogId }),
                  entries[index].unlockedAt != nil,
                  entries[index].assignedProjects.isEmpty,
                  !catalogEntry.unlockCondition.isMet(
                    maxBond: maxBond,
                    totalSpentBits: totalSpentBits,
                    totalVillageBits: totalVillageBits
                  )
            else { continue }
            entries[index].unlockedAt = nil
            changed = true
        }
        return changed
    }

    mutating func mergeMissingCatalogEntries(from catalog: NPCCatalog) {
        let known = Set(entries.map(\.catalogId))
        for entry in catalog.entries where !known.contains(entry.catalogId) {
            entries.append(RosterEntry(
                catalogId: entry.catalogId,
                name: entry.defaultName ?? entry.catalogId,
                unlockedAt: nil,
                assignedProjects: []
            ))
        }
        entries.sort { lhs, rhs in
            let left = catalog.entries.firstIndex { $0.catalogId == lhs.catalogId } ?? Int.max
            let right = catalog.entries.firstIndex { $0.catalogId == rhs.catalogId } ?? Int.max
            return left < right
        }
    }

    private static func uniqueSorted(_ paths: [String]) -> [String] {
        Array(Set(paths)).sorted()
    }
}
