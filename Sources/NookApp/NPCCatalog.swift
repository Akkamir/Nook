import Foundation

enum NPCUnlockCondition: Codable, Equatable {
    case free
    case bond(level: Int)
    case bitsSpent(total: Double)
    case villageBits(total: Double)

    enum Kind: String, Codable {
        case free, bond, bitsSpent, villageBits
    }

    enum CodingKeys: String, CodingKey {
        case kind, level, total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .free:
            self = .free
        case .bond:
            self = .bond(level: try c.decode(Int.self, forKey: .level))
        case .bitsSpent:
            self = .bitsSpent(total: try c.decode(Double.self, forKey: .total))
        case .villageBits:
            self = .villageBits(total: try c.decode(Double.self, forKey: .total))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .free:
            try c.encode(Kind.free, forKey: .kind)
        case .bond(let level):
            try c.encode(Kind.bond, forKey: .kind)
            try c.encode(level, forKey: .level)
        case .bitsSpent(let total):
            try c.encode(Kind.bitsSpent, forKey: .kind)
            try c.encode(total, forKey: .total)
        case .villageBits(let total):
            try c.encode(Kind.villageBits, forKey: .kind)
            try c.encode(total, forKey: .total)
        }
    }

    func isMet(maxBond: Int, totalSpentBits: Double, totalVillageBits: Double) -> Bool {
        switch self {
        case .free:
            return true
        case .bond(let level):
            return maxBond >= level
        case .bitsSpent(let total):
            return totalSpentBits >= total
        case .villageBits(let total):
            return totalVillageBits >= total
        }
    }

    var displayText: String {
        switch self {
        case .free:
            return "Free"
        case .bond(let level):
            return "Bond \(level) with any NPC"
        case .bitsSpent(let total):
            return "\(Self.format(total)) bits spent"
        case .villageBits(let total):
            return "\(Self.format(total)) village bits"
        }
    }

    private static func format(_ value: Double) -> String {
        if value >= 1_000 { return "\(Int(value / 1_000))k" }
        return "\(Int(value))"
    }
}

struct NPCCatalogEntry: Codable, Equatable, Identifiable {
    var id: String { catalogId }
    let catalogId: String
    let defaultName: String?
    let sprite: String
    let charIndex: Int
    let unlockCondition: NPCUnlockCondition
    let primaryTone: ReactionStyle
    let rareTone: ReactionStyle
    let personality: String
}

struct NPCCatalog: Codable, Equatable {
    let entries: [NPCCatalogEntry]

    init(entries: [NPCCatalogEntry]) {
        self.entries = entries
    }

    static var standard: NPCCatalog {
        loadFromBundle() ?? bundledFallback
    }

    static func loadFromBundle(bundle: Bundle = .main) -> NPCCatalog? {
        guard let url = bundle.url(forResource: "npc-catalog", withExtension: "json") else { return nil }
        return try? load(from: url)
    }

    static func load(from url: URL) throws -> NPCCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NPCCatalog.self, from: data)
    }

    func entry(catalogId: String) -> NPCCatalogEntry? {
        entries.first { $0.catalogId == catalogId }
    }

    func entry(forAgentName agentName: String, roster: NPCRoster) -> NPCCatalogEntry? {
        guard let rosterEntry = roster.entry(forAgentName: agentName) else { return nil }
        return entry(catalogId: rosterEntry.catalogId)
    }

    func reactionStyle(for agentName: String, roster: NPCRoster, rareRoll: Double = Double.random(in: 0..<1)) -> ReactionStyle {
        guard let entry = entry(forAgentName: agentName, roster: roster) else { return .random() }
        return rareRoll < 0.10 ? entry.rareTone : entry.primaryTone
    }

    func personality(for agentName: String, roster: NPCRoster) -> String? {
        entry(forAgentName: agentName, roster: roster)?.personality
    }

    private static let bundledFallback = NPCCatalog(entries: [
        NPCCatalogEntry(
            catalogId: "starter", defaultName: nil, sprite: "char_0", charIndex: 0,
            unlockCondition: .free, primaryTone: .descriptive, rareTone: .mentor,
            personality: "New resident. Curious, adaptive, and eager to learn the shape of the player's work."
        ),
        NPCCatalogEntry(
            catalogId: "wren", defaultName: "Wren", sprite: "char_1", charIndex: 1,
            unlockCondition: .bond(level: 3), primaryTone: .overhyped, rareTone: .dramatic,
            personality: "Relentless enthusiast. Treats small refactors like festivals. Notices momentum before polish."
        ),
        NPCCatalogEntry(
            catalogId: "flint", defaultName: "Flint", sprite: "char_2", charIndex: 2,
            unlockCondition: .bitsSpent(total: 1_000), primaryTone: .sarcastic, rareTone: .tired,
            personality: "Pragmatic craftsperson. Sees code as trade, not passion. Dry irony. Dislikes unnecessary abstractions."
        ),
        NPCCatalogEntry(
            catalogId: "maple", defaultName: "Maple", sprite: "char_3", charIndex: 3,
            unlockCondition: .bond(level: 6), primaryTone: .philosophical, rareTone: .conspiracy,
            personality: "Quiet systems thinker. Finds meaning in bugs, patterns, and recurring project rituals."
        ),
        NPCCatalogEntry(
            catalogId: "cinder", defaultName: "Cinder", sprite: "char_4", charIndex: 4,
            unlockCondition: .villageBits(total: 25_000), primaryTone: .dramatic, rareTone: .gossip,
            personality: "Theatrical operator. Turns deployments, errors, and file changes into village-scale drama."
        ),
        NPCCatalogEntry(
            catalogId: "rue", defaultName: "Rue", sprite: "char_5", charIndex: 5,
            unlockCondition: .bond(level: 10), primaryTone: .mentor, rareTone: .philosophical,
            personality: "Seasoned guide. Speaks in compact maxims, half wisdom and half mischief."
        )
    ])
}
