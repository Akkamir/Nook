import Foundation
import Observation

@MainActor
@Observable
final class VillageEngine {
    private(set) var totalBits: Double = 0
    private(set) var pendingBits: Double = 0
    private(set) var agents: [String: AgentRecord] = [:]
    private(set) var sessions: [String: SessionRecord] = [:]
    private(set) var upgrades: UpgradeState = .empty
    private(set) var npcMemory: NPCMemoryState = .empty

    private(set) var dayPhase: DayPhase = DayPhase.current()
    private(set) var activeSessions: Set<String> = []
    private(set) var activeSessionCounts: [String: Int] = [:]
    var newBitEvents: [BitEvent] = []
    var newActivityEvents: [SessionActivityEvent] = []

    private let ledgerURL: URL
    private let upgradeStore: UpgradeFileStore
    private let memoryStore: NPCMemoryStore
    private let narrationClient: OpenAINarrationClient
    private let decoder: JSONDecoder
    private let watcher: LedgerWatcher
    private var isRunning = false
    private var lastSeenEventSeq: Int = -1
    private var lastSeenActivitySeq: Int = -1
    private var dayNightTimer: DispatchSourceTimer?
    private var sessionTimer: DispatchSourceTimer?
    private let sessionDetector = SessionDetector()
    private let hookServer = ClaudeHookServer()
    private let hookInstaller = ClaudeHookInstaller()
    private let claudeProjectsWatcher = ClaudeProjectsWatcher()

    init(
        ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/ledger.json"),
        upgradeStore: UpgradeFileStore = .production,
        memoryStore: NPCMemoryStore = NPCMemoryStore(),
        narrationClient: OpenAINarrationClient = OpenAINarrationClient()
    ) {
        self.ledgerURL = ledgerURL
        self.upgradeStore = upgradeStore
        self.memoryStore = memoryStore
        self.narrationClient = narrationClient
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
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
    }

    func stop() {
        watcher.stop()
        dayNightTimer?.cancel()
        dayNightTimer = nil
        sessionTimer?.cancel()
        sessionTimer = nil
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
        guard let data = try? Data(contentsOf: ledgerURL),
              var state = try? decoder.decode(LedgerState.self, from: data)
        else { return }
        state.pendingBits = 0
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(state) else { return }
        try? encoded.write(to: ledgerURL, options: .atomic)
    }

    func availableBits(for agentName: String) -> Double {
        let ledger = LedgerState(
            totalBits: totalBits,
            pendingBits: pendingBits,
            agents: agents,
            lastUpdated: Date(),
            recentEvents: [],
            eventSeq: 0,
            sessions: sessions
        )
        return UpgradeEconomy.availableBits(for: agentName, ledger: ledger, upgrades: upgrades)
    }

    func nextBitMultiplierCost(for agentName: String) -> Double {
        let level = upgrades.agents[agentName]?.bitMultiplierLevel ?? 0
        return UpgradeEconomy.cost(for: .bitMultiplier, currentLevel: level)
    }

    func requestBitMultiplierPurchase(for agentName: String) {
        let request = UpgradePurchaseRequest(agentName: agentName, upgrade: .bitMultiplier, requestedAt: Date())
        do {
            try upgradeStore.append(request)
        } catch {
            print("Nook upgrade purchase request failed: \(error)")
        }
    }

    private func reload() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let state = try? decoder.decode(LedgerState.self, from: data)
        else { return }
        totalBits = state.totalBits
        pendingBits = state.pendingBits
        agents = state.agents
        sessions = state.sessions
        upgrades = upgradeStore.load()
        refreshMemoryCache(for: state.sessions)

        if lastSeenEventSeq == -1 {
            // First load: anchor to current position, don't replay old events.
            lastSeenEventSeq = state.eventSeq
            lastSeenActivitySeq = state.activitySeq
            return
        }

        let fresh = state.recentEvents.filter { $0.seq > lastSeenEventSeq }
        if !fresh.isEmpty {
            newBitEvents += fresh
            lastSeenEventSeq = fresh.map(\.seq).max() ?? lastSeenEventSeq
        }

        let freshActivity = state.recentActivity.filter { $0.seq > lastSeenActivitySeq }
        if !freshActivity.isEmpty {
            newActivityEvents += freshActivity
            lastSeenActivitySeq = freshActivity.map(\.seq).max() ?? lastSeenActivitySeq
        }
    }

    private func refreshMemoryCache(for sessions: [String: SessionRecord]) {
        var memory = memoryStore.load()
        var changed = false
        for session in sessions.values where memory.sessions[session.sessionId] == nil {
            memory.sessions[session.sessionId] = GeneratedSessionMemory.heuristic(for: session)
            changed = true
        }
        if changed {
            try? memoryStore.save(memory)
        }
        npcMemory = memory
    }

    private func updateMemoryFromHook(_ event: ClaudeHookEvent) async {
        guard event.refreshesActivity,
              let sessionId = event.sessionId,
              let transcriptPath = event.transcriptPath,
              let session = sessions[sessionId],
              let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8)
        else { return }

        let digest = SessionDigest.fromTranscript(content, project: session.project)
        var memory = memoryStore.load()
        let base = memory.sessions[sessionId] ?? GeneratedSessionMemory.heuristic(for: session)
        memory.sessions[sessionId] = base
        try? memoryStore.save(memory)
        npcMemory = memory

        guard OpenAIAPIKeyStore.load() != nil else { return }
        if let enriched = try? await narrationClient.enrich(
            sessionMemory: base,
            digest: digest,
            bond: BondScale.level(for: session.totalTokens)
        ) {
            var latest = memoryStore.load()
            latest.sessions[sessionId] = enriched
            try? memoryStore.save(latest)
            npcMemory = latest
        }
    }
}
