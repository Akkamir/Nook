import XCTest
@testable import Nook

@MainActor
final class NPCRosterTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NPCRosterTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_initial_roster_contains_all_catalog_entries_and_unlocks_starter() throws {
        let catalog = NPCCatalog(entries: [
            entry("starter", defaultName: nil, unlock: .free, primary: .descriptive, rare: .mentor),
            entry("wren", defaultName: "Wren", unlock: .bond(level: 3), primary: .overhyped, rare: .dramatic),
            entry("flint", defaultName: "Flint", unlock: .bitsSpent(total: 1_000), primary: .sarcastic, rare: .tired)
        ])
        let now = date("2026-06-09T10:00:00Z")

        let roster = NPCRoster.initial(
            catalog: catalog,
            starterName: "Radion",
            assignedProjects: ["/Users/mchau/Desktop/Code/Nook"],
            now: now
        )

        XCTAssertEqual(roster.version, 1)
        XCTAssertEqual(roster.entries.map(\.catalogId), ["starter", "wren", "flint"])
        XCTAssertEqual(roster.entry(catalogId: "starter")?.name, "Radion")
        XCTAssertEqual(roster.entry(catalogId: "starter")?.unlockedAt, now)
        XCTAssertEqual(roster.entry(catalogId: "starter")?.assignedProjects, ["/Users/mchau/Desktop/Code/Nook"])
        XCTAssertNil(roster.entry(catalogId: "wren")?.unlockedAt)
        XCTAssertEqual(roster.entry(catalogId: "flint")?.name, "Flint")
    }

    func test_roster_store_assigns_and_unassigns_project_config_files() throws {
        let projectURL = tempDir.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let rosterURL = tempDir.appendingPathComponent("roster.json")
        let store = RosterStore(url: rosterURL, catalog: .standard)
        var roster = NPCRoster.initial(
            catalog: .standard,
            starterName: "Radion",
            assignedProjects: [],
            now: date("2026-06-09T10:00:00Z")
        )

        try store.assign(projectPath: projectURL.path, toCatalogId: "starter", in: &roster)

        let configURL = projectURL.appendingPathComponent(".pixelvillage")
        let data = try Data(contentsOf: configURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object["agent"], "Radion")
        XCTAssertEqual(roster.entry(catalogId: "starter")?.assignedProjects, [projectURL.path])
        XCTAssertEqual(try store.load().entry(catalogId: "starter")?.assignedProjects, [projectURL.path])

        try store.unassign(projectPath: projectURL.path, fromCatalogId: "starter", in: &roster)

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(roster.entry(catalogId: "starter")?.assignedProjects, [])
        XCTAssertEqual(try store.load().entry(catalogId: "starter")?.assignedProjects, [])
    }

    func test_project_assigned_to_one_npc_is_not_assignable_to_another_until_removed() throws {
        let projectURL = tempDir.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let rosterURL = tempDir.appendingPathComponent("roster.json")
        let catalog = NPCCatalog(entries: [
            entry("starter", defaultName: nil, unlock: .free, primary: .descriptive, rare: .mentor),
            entry("wren", defaultName: "Wren", unlock: .free, primary: .overhyped, rare: .dramatic)
        ])
        let store = RosterStore(url: rosterURL, catalog: catalog)
        var roster = NPCRoster(version: 1, entries: [
            RosterEntry(catalogId: "starter", name: "C0", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: []),
            RosterEntry(catalogId: "wren", name: "Wren", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: [])
        ])

        try store.assign(projectPath: projectURL.path, toCatalogId: "starter", in: &roster)
        try store.assign(projectPath: projectURL.path, toCatalogId: "wren", in: &roster)

        XCTAssertEqual(roster.entry(catalogId: "starter")?.assignedProjects, [projectURL.path])
        XCTAssertEqual(roster.entry(catalogId: "wren")?.assignedProjects, [])
        XCTAssertTrue(roster.isProjectAssigned(projectURL.path, excludingCatalogId: "wren"))

        try store.unassign(projectPath: projectURL.path, fromCatalogId: "starter", in: &roster)
        try store.assign(projectPath: projectURL.path, toCatalogId: "wren", in: &roster)

        XCTAssertEqual(roster.entry(catalogId: "starter")?.assignedProjects, [])
        XCTAssertEqual(roster.entry(catalogId: "wren")?.assignedProjects, [projectURL.path])
    }

    func test_available_projects_excludes_projects_assigned_to_other_npcs() {
        let current = DiscoveredProject(path: "/current", displayName: "Current", lastActivityAt: date("2026-06-09T10:00:00Z"))
        let taken = DiscoveredProject(path: "/taken", displayName: "Taken", lastActivityAt: date("2026-06-09T10:00:00Z"))
        let free = DiscoveredProject(path: "/free", displayName: "Free", lastActivityAt: date("2026-06-09T10:00:00Z"))
        let roster = NPCRoster(version: 1, entries: [
            RosterEntry(catalogId: "starter", name: "C0", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: [current.path]),
            RosterEntry(catalogId: "wren", name: "Wren", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: [taken.path])
        ])

        let available = roster.availableProjects(from: [current, taken, free], forCatalogId: "starter")

        XCTAssertEqual(available.map(\.path), [current.path, free.path])
    }

    func test_catalog_lookup_uses_roster_name_for_style_and_personality() {
        let catalog = NPCCatalog(entries: [
            entry("flint", defaultName: "Flint", unlock: .bitsSpent(total: 1_000), primary: .sarcastic, rare: .tired)
        ])
        let roster = NPCRoster(version: 1, entries: [
            RosterEntry(catalogId: "flint", name: "Forge", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: [])
        ])

        XCTAssertEqual(catalog.entry(forAgentName: "Forge", roster: roster)?.catalogId, "flint")
        XCTAssertEqual(catalog.reactionStyle(for: "Forge", roster: roster, rareRoll: 0.50), .sarcastic)
        XCTAssertEqual(catalog.reactionStyle(for: "Forge", roster: roster, rareRoll: 0.05), .tired)
        XCTAssertEqual(catalog.personality(for: "Forge", roster: roster), "flint personality")
        XCTAssertNil(catalog.entry(forAgentName: "Missing", roster: roster))
    }

    func test_unlock_conditions_use_bond_spent_bits_and_total_village_bits() {
        var roster = NPCRoster(version: 1, entries: [
            RosterEntry(catalogId: "wren", name: "Wren", unlockedAt: nil, assignedProjects: []),
            RosterEntry(catalogId: "flint", name: "Flint", unlockedAt: nil, assignedProjects: []),
            RosterEntry(catalogId: "cinder", name: "Cinder", unlockedAt: nil, assignedProjects: [])
        ])
        let catalog = NPCCatalog(entries: [
            entry("wren", defaultName: "Wren", unlock: .bond(level: 3), primary: .overhyped, rare: .dramatic),
            entry("flint", defaultName: "Flint", unlock: .bitsSpent(total: 1_000), primary: .sarcastic, rare: .tired),
            entry("cinder", defaultName: "Cinder", unlock: .villageBits(total: 25_000), primary: .dramatic, rare: .gossip)
        ])
        let now = date("2026-06-09T10:00:00Z")

        let unlocked = roster.unlockEligibleEntries(
            catalog: catalog,
            maxBond: 6,
            totalSpentBits: 1_200,
            totalVillageBits: 24_999,
            now: now
        )

        XCTAssertEqual(unlocked, ["wren", "flint"])
        XCTAssertEqual(roster.entry(catalogId: "wren")?.unlockedAt, now)
        XCTAssertEqual(roster.entry(catalogId: "flint")?.unlockedAt, now)
        XCTAssertNil(roster.entry(catalogId: "cinder")?.unlockedAt)
    }

    func test_relock_ineligible_unassigned_entries_after_unlock_source_correction() {
        var roster = NPCRoster(version: 1, entries: [
            RosterEntry(catalogId: "cinder", name: "Cinder", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: []),
            RosterEntry(catalogId: "rue", name: "Rue", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: ["/repo"])
        ])
        let catalog = NPCCatalog(entries: [
            entry("cinder", defaultName: "Cinder", unlock: .villageBits(total: 25_000), primary: .dramatic, rare: .gossip),
            entry("rue", defaultName: "Rue", unlock: .bond(level: 10), primary: .mentor, rare: .philosophical)
        ])

        let changed = roster.relockIneligibleUnassignedEntries(
            catalog: catalog,
            maxBond: 3,
            totalSpentBits: 0,
            totalVillageBits: 6_700
        )

        XCTAssertTrue(changed)
        XCTAssertNil(roster.entry(catalogId: "cinder")?.unlockedAt)
        XCTAssertNotNil(roster.entry(catalogId: "rue")?.unlockedAt)
    }

    func test_visible_npc_records_include_assigned_unlocked_roster_entry_without_ledger_agent() throws {
        let catalog = NPCCatalog(entries: [
            entry("starter", defaultName: nil, unlock: .free, primary: .descriptive, rare: .mentor)
        ])
        let rosterURL = tempDir.appendingPathComponent("roster.json")
        let rosterStore = RosterStore(url: rosterURL, catalog: catalog)
        let roster = NPCRoster.initial(
            catalog: catalog,
            starterName: "C0",
            assignedProjects: ["/repo"],
            now: date("2026-06-09T10:00:00Z")
        )
        try rosterStore.save(roster)

        let engine = VillageEngine(
            ledgerURL: tempDir.appendingPathComponent("ledger.json"),
            economyStore: EconomyStore(url: tempDir.appendingPathComponent("economy.json")),
            memoryStore: NPCMemoryStore(url: tempDir.appendingPathComponent("memory.json")),
            npcCatalog: catalog,
            rosterStore: rosterStore
        )

        XCTAssertEqual(engine.visibleNPCRecords["C0"]?.name, "C0")
        XCTAssertEqual(engine.visibleNPCRecords["C0"]?.bond, 1)
        XCTAssertEqual(engine.visibleNPCRecords["C0"]?.totalTokens, 0)
    }

    func test_shop_records_include_unassigned_unlocked_roster_entries_without_ledger_agent() throws {
        let catalog = NPCCatalog(entries: [
            entry("starter", defaultName: nil, unlock: .free, primary: .descriptive, rare: .mentor),
            entry("wren", defaultName: "Wren", unlock: .free, primary: .overhyped, rare: .dramatic)
        ])
        let rosterURL = tempDir.appendingPathComponent("roster.json")
        let rosterStore = RosterStore(url: rosterURL, catalog: catalog)
        let roster = NPCRoster(version: 1, entries: [
            RosterEntry(catalogId: "starter", name: "C0", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: ["/repo"]),
            RosterEntry(catalogId: "wren", name: "Wren", unlockedAt: date("2026-06-09T10:00:00Z"), assignedProjects: [])
        ])
        try rosterStore.save(roster)

        let engine = VillageEngine(
            ledgerURL: tempDir.appendingPathComponent("ledger.json"),
            economyStore: EconomyStore(url: tempDir.appendingPathComponent("economy.json")),
            memoryStore: NPCMemoryStore(url: tempDir.appendingPathComponent("memory.json")),
            npcCatalog: catalog,
            rosterStore: rosterStore
        )

        XCTAssertNil(engine.visibleNPCRecords["Wren"])
        XCTAssertEqual(engine.shopNPCRecords["Wren"]?.name, "Wren")
        XCTAssertEqual(engine.shopNPCRecords["Wren"]?.bond, 1)
    }

    func test_shop_purchase_works_for_unassigned_unlocked_roster_entries_without_ledger_agent() throws {
        let ledger = LedgerState(
            totalBitsRaw: 0,
            pendingBits: 0,
            globalBitsRaw: 0,
            agents: [
                "Wren": AgentRecord(name: "Wren", totalTokens: 0, bond: 1, totalBitsRaw: 0)
            ],
            lastUpdated: date("2026-06-09T10:00:00Z"),
            recentEvents: [],
            eventSeq: 0,
            sessions: [:]
        )
        var economy = EconomyState.empty
        economy.agents["Wren"] = AgentEconomyState(wallet: 1_000)

        XCTAssertTrue(EconomyEngine.apply(.bitMultiplier, for: "Wren", ledger: ledger, economy: &economy))
        XCTAssertEqual(economy.agents["Wren"]?.bitMultiplierLevel, 1)
    }

    private func entry(
        _ id: String,
        defaultName: String?,
        unlock: NPCUnlockCondition,
        primary: ReactionStyle,
        rare: ReactionStyle
    ) -> NPCCatalogEntry {
        NPCCatalogEntry(
            catalogId: id,
            defaultName: defaultName,
            sprite: "char_0",
            charIndex: 0,
            unlockCondition: unlock,
            primaryTone: primary,
            rareTone: rare,
            personality: "\(id) personality"
        )
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
