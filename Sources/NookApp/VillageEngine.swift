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

    private(set) var dayPhase: DayPhase = DayPhase.current()
    private(set) var activeSessions: Set<String> = []
    private(set) var activeSessionCounts: [String: Int] = [:]
    var newBitEvents: [BitEvent] = []
    var newActivityEvents: [SessionActivityEvent] = []

    private let ledgerURL: URL
    private let economyStore: EconomyStore
    private let memoryStore: NPCMemoryStore
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
        narrationClient: OpenAINarrationClient = OpenAINarrationClient()
    ) {
        self.ledgerURL = ledgerURL
        self.economyStore = economyStore
        self.memoryStore = memoryStore
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
                await self.updateMemoryFromHook(event)
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

    func effectiveMultiplier(for agentName: String) -> Double {
        guard let agent = agents[agentName], let state = upgrades.agents[agentName] else { return 1.0 }
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
        return EconomyEngine.cost(for: .bitMultiplier, currentLevel: level)
    }

    func nextBondDividendCost(for agentName: String) -> Double {
        let level = upgrades.agents[agentName]?.bondDividendLevel ?? 0
        return EconomyEngine.cost(for: .bondDividend, currentLevel: level)
    }

    func nextTrickleCost(for agentName: String) -> Double {
        let level = upgrades.agents[agentName]?.trickleCount ?? 0
        return EconomyEngine.cost(for: .trickle, currentLevel: level)
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
            agents: agents,
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
        let url = economyStore.url
        let stateToSave = updatedUpgrades
        Task.detached(priority: .utility) {
            let store = EconomyStore(url: url)
            try? store.save(stateToSave)
        }
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
                pastSessions: Array(pastSessions.suffix(5))
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
        guard lastLiveCommentAt[agentName].map({ now.timeIntervalSince($0) > 120 }) ?? true else { return }
        do {
            let line = try await narrationClient.liveComment(digest: digest, bond: bond, totalTokens: totalTokens)
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
