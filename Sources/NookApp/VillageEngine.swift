import Foundation
import Observation

@MainActor
@Observable
final class VillageEngine {
    private(set) var totalBitsRaw: Double = 0
    private(set) var pendingBits: Double = 0
    private(set) var globalBitsRaw: Double = 0
    private(set) var agents: [String: AgentRecord] = [:]
    private(set) var sessions: [String: SessionRecord] = [:]
    private(set) var upgrades: EconomyState = .empty
    private(set) var npcMemory: NPCMemoryState = .empty
    private(set) var roster: NPCRoster
    private(set) var newlyUnlockedNPCIDs: [String] = []
    private(set) var shouldOfferGlobalGitignore = false

    private(set) var dayPhase: DayPhase = DayPhase.current()
    private(set) var activeSessions: Set<String> = []
    private(set) var activeSessionCounts: [String: Int] = [:]
    var newBitEvents: [BitEvent] = []
    var newActivityEvents: [SessionActivityEvent] = []

    private let ledgerURL: URL
    private let economyStore: EconomyStore
    private let memoryStore: NPCMemoryStore
    let npcCatalog: NPCCatalog
    private let rosterStore: RosterStore
    private let gitignoreAdvisor = GitignoreAdvisor()
    private let narrationClient: OpenAINarrationClient
    private let watcher: LedgerWatcher
    private var isRunning = false
    private var lastSeenEventSeq: Int = -1
    private var lastSeenActivitySeq: Int = -1
    private var dayNightTimer: DispatchSourceTimer?
    private var sessionTimer: DispatchSourceTimer?
    private var trickleTimer: DispatchSourceTimer?
    private var trickleInitialized = false
    private var lastLiveCommentAt: [String: Date] = [:]
    private var lastPromptReactionAt: [String: Date] = [:]
    private var lastResponseReactionAt: [String: Date] = [:]
    private var lastReactedMessage: [String: String] = [:]   // agentName → message we last reacted to
    var onTrickleGain: ((String, Double) -> Void)?
    var onLiveComment: ((String, String) -> Void)?
    private let sessionDetector = SessionDetector()
    private let hookServer = ClaudeHookServer()
    private let hookInstaller = ClaudeHookInstaller()
    private let claudeProjectsWatcher = ClaudeProjectsWatcher()

    init(
        ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/ledger.json"),
        economyStore: EconomyStore = .production,
        memoryStore: NPCMemoryStore = NPCMemoryStore(),
        npcCatalog: NPCCatalog = .standard,
        rosterStore: RosterStore? = nil,
        narrationClient: OpenAINarrationClient = OpenAINarrationClient()
    ) {
        self.ledgerURL = ledgerURL
        self.economyStore = economyStore
        self.memoryStore = memoryStore
        self.npcCatalog = npcCatalog
        let resolvedRosterStore = rosterStore ?? RosterStore(catalog: npcCatalog)
        self.rosterStore = resolvedRosterStore
        self.roster = resolvedRosterStore.loadOrLockedRoster()
        self.narrationClient = narrationClient
        self.watcher = LedgerWatcher(ledgerURL: ledgerURL)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        DaemonInstaller.shared.installIfNeeded()
        watcher.onChange = { [weak self] in self?.reload() }
        watcher.start()
        reload()
        startDayNightTimer()
        startHookServer()
        startClaudeProjectsWatcher()
        startSessionTimer()
        startTrickleTimer()
    }

    func stop() {
        watcher.stop()
        dayNightTimer?.cancel()
        dayNightTimer = nil
        sessionTimer?.cancel()
        sessionTimer = nil
        trickleTimer?.cancel()
        trickleTimer = nil
        claudeProjectsWatcher.stop()
        hookServer.stop()
        isRunning = false
    }

    private func startHookServer() {
        hookServer.onEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                let changed = await self.sessionDetector.handleHookEvent(event)
                if changed {
                    await self.refreshActiveSessionCounts()
                }
                if event.refreshesActivity {
                    await self.updateMemoryFromHook(event)
                }
                if event.isPromptStart {
                    await self.handlePromptStart(event)
                }
                if event.isClaudeResponse {
                    await self.handleClaudeResponse(event)
                }
            }
        }

        do {
            try hookServer.start()
            try hookInstaller.install()
        } catch {
            print("Nook Claude hooks disabled: \(error)")
        }
    }

    private func startClaudeProjectsWatcher() {
        claudeProjectsWatcher.onChange = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshActiveSessionCounts()
            }
        }
        claudeProjectsWatcher.start()
    }

    private func startSessionTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(120))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshActiveSessionCounts()
            }
        }
        timer.resume()
        sessionTimer = timer
    }

    private func refreshActiveSessionCounts() async {
        let counts = await sessionDetector.detectActiveCounts()
        activeSessionCounts = counts
        activeSessions = Set(counts.keys)
    }

    private func startDayNightTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(60))
        timer.setEventHandler { [weak self] in
            self?.dayPhase = DayPhase.current()
        }
        timer.resume()
        dayNightTimer = timer
    }

    func consumePendingBits() {
        pendingBits = 0
        let url = ledgerURL
        Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: url),
                  var state = try? decoder.decode(LedgerState.self, from: data)
            else { return }
            state.pendingBits = 0
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let encoded = try? encoder.encode(state) else { return }
            try? encoded.write(to: url, options: .atomic)
        }
    }

    var totalAvailableBits: Double {
        upgrades.agents.values.reduce(0) { $0 + $1.availableBits }
    }

    var villageAvailableBits: Double {
        upgrades.villageAvailableBits
    }

    var needsOnboarding: Bool {
        roster.needsOnboarding
    }

    var hasRosterBadge: Bool {
        !newlyUnlockedNPCIDs.isEmpty || roster.entries.contains { $0.isUnlocked && $0.assignedProjects.isEmpty }
    }

    var discoveredProjects: [DiscoveredProject] {
        ProjectDiscovery().discover()
    }

    var shopNPCRecords: [String: AgentRecord] {
        var records = agents
        for entry in roster.entries where entry.isUnlocked {
            if records[entry.name] == nil {
                records[entry.name] = AgentRecord(name: entry.name, totalTokens: 0, bond: 1, totalBitsRaw: 0)
            }
        }
        return records
    }

    var visibleNPCRecords: [String: AgentRecord] {
        var records = agents
        for entry in roster.entries where entry.isUnlocked && !entry.assignedProjects.isEmpty {
            if records[entry.name] == nil {
                records[entry.name] = AgentRecord(name: entry.name, totalTokens: 0, bond: 1, totalBitsRaw: 0)
            }
        }
        return records
    }

    func consumeRosterBadge() {
        newlyUnlockedNPCIDs.removeAll()
    }

    func addPixelVillageToGlobalGitignore() {
        do {
            try gitignoreAdvisor.addPixelVillageToGlobalGitignore()
            shouldOfferGlobalGitignore = false
        } catch {
            print("[Nook] global gitignore update error: \(error)")
        }
    }

    func createStarterNPC(name: String, projectPaths: [String]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let starterName = trimmed.isEmpty ? "Resident" : trimmed
        var next = NPCRoster.initial(catalog: npcCatalog, starterName: starterName, assignedProjects: [], now: Date())
        do {
            try rosterStore.save(next)
            for path in projectPaths {
                try rosterStore.assign(projectPath: path, toCatalogId: "starter", in: &next)
            }
            shouldOfferGlobalGitignore = gitignoreAdvisor.needsGlobalIgnoreOffer(forProjectPaths: projectPaths)
            roster = next
        } catch {
            print("[Nook] starter roster save error: \(error)")
        }
    }

    func saveRosterAssignment(catalogId: String, name: String, projectPaths: [String]) {
        var next = roster
        if canRenameRosterEntry(catalogId: catalogId) {
            next.rename(catalogId: catalogId, to: name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let assignablePaths = projectPaths.filter { path in
            !next.isProjectAssigned(path, excludingCatalogId: catalogId)
        }
        do {
            try rosterStore.applyAssignments(forCatalogId: catalogId, newProjectPaths: assignablePaths, roster: &next)
            if let entry = next.entry(catalogId: catalogId) {
                for path in entry.assignedProjects {
                    try rosterStore.assign(projectPath: path, toCatalogId: catalogId, in: &next)
                }
            }
            shouldOfferGlobalGitignore = gitignoreAdvisor.needsGlobalIgnoreOffer(forProjectPaths: assignablePaths)
            roster = next
        } catch {
            print("[Nook] roster assignment error: \(error)")
        }
    }

    func canRenameRosterEntry(catalogId: String) -> Bool {
        guard let entry = roster.entry(catalogId: catalogId) else { return false }
        return !sessions.values.contains { $0.agentName == entry.name }
    }

    func effectiveMultiplier(for agentName: String) -> Double {
        guard let agent = shopNPCRecords[agentName], let state = upgrades.agents[agentName] else { return 1.0 }
        return EconomyEngine.effectiveMultiplier(for: state, bond: agent.bond)
    }

    private func backgroundSaveUpgrades(_ state: UpgradeState) {
        let url = economyStore.url
        Task.detached(priority: .utility) {
            let store = EconomyStore(url: url)
            try? store.save(state)
        }
    }

    func availableBits(for agentName: String) -> Double {
        upgrades.agents[agentName]?.availableBits ?? 0
    }

    func bitMultiplier(for agentName: String) -> Double {
        upgrades.agents[agentName]?.bitMultiplier ?? 1.0
    }

    func nextBitMultiplierCost(for agentName: String) -> Double {
        let level = upgrades.agents[agentName]?.bitMultiplierLevel ?? 0
        guard EconomyEngine.canBuy(.bitMultiplier, currentLevel: level, bond: shopNPCRecords[agentName]?.bond ?? 0) else { return .infinity }
        return EconomyEngine.cost(for: .bitMultiplier, currentLevel: level)
    }

    func nextBondDividendCost(for agentName: String) -> Double {
        let level = upgrades.agents[agentName]?.bondDividendLevel ?? 0
        let bond = shopNPCRecords[agentName]?.bond ?? 0
        guard EconomyEngine.canBuy(.bondDividend, currentLevel: level, bond: bond) else { return .infinity }
        return EconomyEngine.cost(for: .bondDividend, currentLevel: level)
    }

    func nextTrickleCost(for agentName: String) -> Double {
        let count = upgrades.agents[agentName]?.trickleCount ?? 0
        let bond = shopNPCRecords[agentName]?.bond ?? 0
        guard EconomyEngine.canBuy(.trickle, currentLevel: count, bond: bond) else { return .infinity }
        return EconomyEngine.cost(for: .trickle, currentLevel: count)
    }

    func requestBitMultiplierPurchase(for agentName: String) {
        requestPurchase(.bitMultiplier, for: agentName)
    }

    func requestBondDividendPurchase(for agentName: String) {
        requestPurchase(.bondDividend, for: agentName)
    }

    func requestTricklePurchase(for agentName: String) {
        requestPurchase(.trickle, for: agentName)
    }

    private func requestPurchase(_ kind: UpgradeKind, for agentName: String) {
        let ledger = LedgerState(
            totalBitsRaw: totalBitsRaw,
            pendingBits: pendingBits,
            globalBitsRaw: globalBitsRaw,
            agents: shopNPCRecords,
            lastUpdated: Date(),
            recentEvents: [],
            eventSeq: 0,
            sessions: sessions
        )
        var updated = upgrades
        guard EconomyEngine.apply(kind, for: agentName, ledger: ledger, economy: &updated) else { return }
        upgrades = updated
        backgroundSaveUpgrades(updated)
    }

    private func startTrickleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: .seconds(10))
        timer.setEventHandler { [weak self] in self?.tickTrickle() }
        timer.resume()
        trickleTimer = timer
    }

    // animate: false during startup catchup (sprites may not be ready yet)
    private func tickTrickle(animate: Bool = true) {
        let now = Date()
        var updatedUpgrades = upgrades
        var changed = false

        for (agentName, _) in agents {
            var state = updatedUpgrades.agents[agentName] ?? AgentUpgradeState()
            guard state.trickleCount > 0 else {
                if state.lastTrickleAt == nil {
                    state.lastTrickleAt = now
                    updatedUpgrades.agents[agentName] = state
                    changed = true
                }
                continue
            }

            let elapsed: TimeInterval
            if let last = state.lastTrickleAt {
                // 1h offline cap: prevents dumping 24h of trickle on first open.
                elapsed = min(now.timeIntervalSince(last), 3600)
            } else {
                elapsed = 0
            }

            // Rate is bits per 10s; compute proportionally over elapsed seconds.
            let rate = EconomyEngine.trickleRate(count: state.trickleCount)
            let gained = rate * elapsed / 10.0
            state.trickleBitsAccumulated += gained

            state.lastTrickleAt = now
            updatedUpgrades.agents[agentName] = state
            changed = true

            // Skip animation for sub-bit gains and for offline catchup.
            if animate && gained >= 0.5 {
                onTrickleGain?(agentName, gained)
            }
        }

        guard changed else { return }
        upgrades = updatedUpgrades
        backgroundSaveUpgrades(updatedUpgrades)
    }

    private func reload() {
        let ledgerURL = self.ledgerURL
        let economyURL = economyStore.url
        let memoryURL = memoryStore.url
        let anchored = lastSeenEventSeq == -1

        Task { [weak self] in
            guard let self else { return }
            guard let snapshot = await Self.loadAll(
                ledgerURL: ledgerURL,
                economyURL: economyURL,
                memoryURL: memoryURL
            ) else { return }
            self.applyReload(ledger: snapshot.ledger, upgrades: snapshot.upgrades, memory: snapshot.memory, anchor: anchored)
        }
    }

    private func applyReload(ledger: LedgerState, upgrades: EconomyState, memory: NPCMemoryState, anchor: Bool) {
        totalBitsRaw = ledger.totalBitsRaw
        pendingBits = ledger.pendingBits
        globalBitsRaw = ledger.globalBitsRaw
        agents = ledger.agents
        sessions = ledger.sessions

        var processedEconomy = upgrades
        EconomyEngine.processLedgerDelta(ledger: ledger, economy: &processedEconomy)
        self.upgrades = processedEconomy
        if processedEconomy != upgrades {
            backgroundSaveUpgrades(processedEconomy)
        }

        npcMemory = memory
        evaluateRosterUnlocks(ledger: ledger, economy: processedEconomy)

        if anchor {
            lastSeenEventSeq = ledger.eventSeq
            lastSeenActivitySeq = ledger.activitySeq
            if !trickleInitialized {
                trickleInitialized = true
                tickTrickle(animate: false)
            }
            return
        }

        let fresh = ledger.recentEvents.filter { $0.seq > lastSeenEventSeq }
        if !fresh.isEmpty {
            newBitEvents += fresh
            lastSeenEventSeq = fresh.map(\.seq).max() ?? lastSeenEventSeq
        }

        let freshActivity = ledger.recentActivity.filter { $0.seq > lastSeenActivitySeq }
        if !freshActivity.isEmpty {
            newActivityEvents += freshActivity
            lastSeenActivitySeq = freshActivity.map(\.seq).max() ?? lastSeenActivitySeq
        }
    }

    private func evaluateRosterUnlocks(ledger: LedgerState, economy: EconomyState) {
        var next = roster
        next.mergeMissingCatalogEntries(from: npcCatalog)
        let maxBond = ledger.agents.values.map(\.bond).max() ?? 0
        let spent = economy.agents.values.reduce(0) { $0 + $1.spentBits }
        let villageBits = economy.villageWallet
        let relocked = next.relockIneligibleUnassignedEntries(
            catalog: npcCatalog,
            maxBond: maxBond,
            totalSpentBits: spent,
            totalVillageBits: villageBits
        )
        let unlocked = next.unlockEligibleEntries(
            catalog: npcCatalog,
            maxBond: maxBond,
            totalSpentBits: spent,
            totalVillageBits: villageBits,
            now: Date()
        )
        roster = next
        guard !unlocked.isEmpty || relocked else { return }
        if !unlocked.isEmpty {
            newlyUnlockedNPCIDs += unlocked
        }
        do {
            try rosterStore.save(next)
        } catch {
            print("[Nook] roster unlock save error: \(error)")
        }
    }

    // Fires on the first tool use of a new user turn (PreToolUse hook).
    // Reads the user's latest message from the transcript and generates a
    // short NPC reaction while Claude is still processing — feels almost live.
    private func handlePromptStart(_ event: ClaudeHookEvent) async {
        guard let sessionId = event.sessionId,
              let transcriptPath = event.transcriptPath,
              let session = sessions[sessionId],
              let agentName = session.agentName
        else { return }

        guard OpenAIAPIKeyStore.load() != nil else { return }

        // Per-NPC throttle: at most once per 30s.
        let now = Date()
        guard lastPromptReactionAt[agentName].map({ now.timeIntervalSince($0) > 30 }) ?? true else { return }

        // Read last user message off main actor (synchronous file I/O).
        let userMessage = await Task.detached(priority: .userInitiated) {
            Self.extractLastUserMessage(from: transcriptPath)
        }.value
        guard let userMessage else { return }

        // Skip if we already reacted to this exact message (same turn, multiple tool uses).
        guard lastReactedMessage[agentName] != userMessage else { return }

        lastReactedMessage[agentName] = userMessage
        lastPromptReactionAt[agentName] = now

        let bond = BondScale.level(for: session.totalTokens)
        let totalTokens = session.totalTokens
        do {
            let style = npcCatalog.reactionStyle(for: agentName, roster: roster)
            let personality = npcCatalog.personality(for: agentName, roster: roster)
            let line = try await narrationClient.promptReaction(
                userMessage: userMessage, bond: bond, totalTokens: totalTokens,
                style: style, personality: personality
            )
            guard !line.isEmpty else { return }
            onLiveComment?(agentName, line)
        } catch {
            print("[Nook] promptReaction error for \(agentName): \(error)")
        }
    }

    // Scans the transcript from the end to find the last plain-text user message.
    // Skips tool results and session-continuation summaries.
    nonisolated private static func extractLastUserMessage(from transcriptPath: String) -> String? {
        guard let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "user",
                  let text = message["content"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !text.hasPrefix("This session is being continued"),
                  !text.hasPrefix("<")
            else { continue }
            return String(text.prefix(300))
        }
        return nil
    }

    // Fires after Claude finishes its response (Stop hook).
    // Extracts the last assistant text and reacts to what Claude just said.
    private func handleClaudeResponse(_ event: ClaudeHookEvent) async {
        guard let sessionId = event.sessionId,
              let transcriptPath = event.transcriptPath,
              let session = sessions[sessionId],
              let agentName = session.agentName
        else { return }

        guard OpenAIAPIKeyStore.load() != nil else { return }

        let now = Date()
        // Per-NPC throttle: at most once per 45s.
        guard lastResponseReactionAt[agentName].map({ now.timeIntervalSince($0) > 45 }) ?? true else { return }
        // liveComment fires on the same Stop event (inside updateMemoryFromHook, which runs first).
        // If it fired within the last 15s we skip to avoid two bubbles on the same response.
        guard lastLiveCommentAt[agentName].map({ now.timeIntervalSince($0) > 15 }) ?? true else { return }

        let snippet = await Task.detached(priority: .userInitiated) {
            Self.extractLastAssistantMessage(from: transcriptPath)
        }.value
        guard let snippet else { return }

        lastResponseReactionAt[agentName] = now
        lastLiveCommentAt[agentName] = now  // claim the shared "NPC just spoke" slot

        let bond = BondScale.level(for: session.totalTokens)
        let totalTokens = session.totalTokens
        do {
            let style = npcCatalog.reactionStyle(for: agentName, roster: roster)
            let personality = npcCatalog.personality(for: agentName, roster: roster)
            let line = try await narrationClient.responseReaction(
                assistantSnippet: snippet, bond: bond, totalTokens: totalTokens,
                style: style, personality: personality
            )
            guard !line.isEmpty else { return }
            onLiveComment?(agentName, line)
        } catch {
            print("[Nook] responseReaction error for \(agentName): \(error)")
        }
    }

    // Scans the transcript from the end to find the last assistant text message.
    // Skips tool_use content blocks, returns only text-bearing assistant turns.
    nonisolated private static func extractLastAssistantMessage(from transcriptPath: String) -> String? {
        guard let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "assistant"
            else { continue }

            let text: String
            if let s = message["content"] as? String {
                text = s
            } else if let blocks = message["content"] as? [[String: Any]] {
                text = blocks
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ")
            } else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return String(trimmed.prefix(300))
        }
        return nil
    }

    private func updateMemoryFromHook(_ event: ClaudeHookEvent) async {
        guard event.refreshesActivity,
              let sessionId = event.sessionId,
              let transcriptPath = event.transcriptPath,
              let session = sessions[sessionId]
        else { return }

        let memoryURL = memoryStore.url
        let project = session.project
        let bond = BondScale.level(for: session.totalTokens)
        let heuristic = GeneratedSessionMemory.heuristic(for: session)

        // All transcript reading + memory I/O off main actor
        let (digest, existingMemory) = await Self.loadHookData(
            transcriptPath: transcriptPath, project: project, memoryURL: memoryURL
        )

        var updatedMemory = existingMemory
        let base = updatedMemory.sessions[sessionId] ?? heuristic
        updatedMemory.sessions[sessionId] = base
        npcMemory = updatedMemory

        Self.backgroundSave(memory: updatedMemory, to: memoryURL)

        guard OpenAIAPIKeyStore.load() != nil else { return }

        let agentName = session.agentName
        let totalTokens = session.totalTokens
        let pastSessions = agentName.map { name in
            existingMemory.sessions.values.filter { $0.agentName == name }
                .sorted { $0.updatedAt < $1.updatedAt }
        } ?? []

        // Enrich stored memory with richer personality-aware prompt.
        do {
            let enriched = try await narrationClient.enrich(
                sessionMemory: base, digest: digest,
                bond: bond, totalTokens: totalTokens,
                pastSessions: Array(pastSessions.suffix(5)),
                personality: agentName.flatMap { npcCatalog.personality(for: $0, roster: roster) }
            )
            updatedMemory.sessions[sessionId] = enriched
            npcMemory = updatedMemory
            Self.backgroundSave(memory: updatedMemory, to: memoryURL)
        } catch {
            print("[Nook] enrich error for session \(sessionId): \(error)")
        }

        // Live spoken line: reacts to what the user is doing right now.
        // Throttled to once per 2 minutes per NPC.
        guard let agentName else { return }
        let now = Date()
        guard lastLiveCommentAt[agentName].map({ now.timeIntervalSince($0) > 60 }) ?? true else { return }
        do {
            let line = try await narrationClient.liveComment(
                digest: digest, bond: bond, totalTokens: totalTokens,
                style: npcCatalog.reactionStyle(for: agentName, roster: roster),
                personality: npcCatalog.personality(for: agentName, roster: roster)
            )
            guard !line.isEmpty else { return }
            lastLiveCommentAt[agentName] = now
            onLiveComment?(agentName, line)
        } catch {
            print("[Nook] liveComment error for \(agentName): \(error)")
        }
    }

    // MARK: - Off-actor I/O helpers

    private struct LoadAllSnapshot {
        let ledger: LedgerState
        let upgrades: UpgradeState
        let memory: NPCMemoryState
    }

    nonisolated private static func loadAll(
        ledgerURL: URL, economyURL: URL, memoryURL: URL
    ) async -> LoadAllSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: ledgerURL),
              let ledger = try? decoder.decode(LedgerState.self, from: data)
        else { return nil }

        // Load economy, with migration from old upgrades.json if needed
        var upgrades: UpgradeState = .empty
        if let eData = try? Data(contentsOf: economyURL),
           let e = try? decoder.decode(UpgradeState.self, from: eData) {
            upgrades = e
        } else {
            // Migration: try old upgrades.json
            let oldURL = economyURL.deletingLastPathComponent().appendingPathComponent("upgrades.json")
            if let oldData = try? Data(contentsOf: oldURL),
               let old = try? decoder.decode(UpgradeState.self, from: oldData) {
                upgrades = old
                // Write to economy.json so next load picks it up
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if let migrated = try? encoder.encode(upgrades) {
                    try? FileManager.default.createDirectory(at: economyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? migrated.write(to: economyURL, options: .atomic)
                }
            }
        }

        var memory: NPCMemoryState
        if let mData = try? Data(contentsOf: memoryURL),
           let m = try? decoder.decode(NPCMemoryState.self, from: mData) {
            memory = m
        } else {
            memory = .empty
        }

        var memoryChanged = false
        for session in ledger.sessions.values where memory.sessions[session.sessionId] == nil {
            memory.sessions[session.sessionId] = GeneratedSessionMemory.heuristic(for: session)
            memoryChanged = true
        }

        if memoryChanged {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let mData = try? encoder.encode(memory) {
                try? FileManager.default.createDirectory(at: memoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? mData.write(to: memoryURL, options: .atomic)
            }
        }

        return LoadAllSnapshot(ledger: ledger, upgrades: upgrades, memory: memory)
    }

    nonisolated private static func loadHookData(
        transcriptPath: String, project: String, memoryURL: URL
    ) async -> (SessionDigest, NPCMemoryState) {
        let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8)
        let digest = content.map { SessionDigest.fromTranscript($0, project: project) }
                     ?? SessionDigest(project: project, branch: nil, recentUserAsks: [], files: [], commands: [], tools: [])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let memory: NPCMemoryState
        if let mData = try? Data(contentsOf: memoryURL),
           let m = try? decoder.decode(NPCMemoryState.self, from: mData) {
            memory = m
        } else {
            memory = .empty
        }

        return (digest, memory)
    }

    nonisolated private static func backgroundSave(memory: NPCMemoryState, to url: URL) {
        Task.detached(priority: .background) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(memory) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
