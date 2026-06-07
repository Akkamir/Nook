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
        let ledgerURL = self.ledgerURL
        let upgradeStateURL = upgradeStore.stateURL
        let memoryURL = memoryStore.url
        let anchored = lastSeenEventSeq == -1

        Task { [weak self] in
            guard let self else { return }
            guard let snapshot = await Self.loadAll(
                ledgerURL: ledgerURL,
                upgradeStateURL: upgradeStateURL,
                memoryURL: memoryURL
            ) else { return }
            self.applyReload(ledger: snapshot.ledger, upgrades: snapshot.upgrades, memory: snapshot.memory, anchor: anchored)
        }
    }

    private func applyReload(ledger: LedgerState, upgrades: UpgradeState, memory: NPCMemoryState, anchor: Bool) {
        totalBits = ledger.totalBits
        pendingBits = ledger.pendingBits
        agents = ledger.agents
        sessions = ledger.sessions
        self.upgrades = upgrades
        npcMemory = memory

        if anchor {
            lastSeenEventSeq = ledger.eventSeq
            lastSeenActivitySeq = ledger.activitySeq
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
        if let enriched = try? await narrationClient.enrich(sessionMemory: base, digest: digest, bond: bond) {
            updatedMemory.sessions[sessionId] = enriched
            npcMemory = updatedMemory
            Self.backgroundSave(memory: updatedMemory, to: memoryURL)
        }
    }

    // MARK: - Off-actor I/O helpers

    private struct LoadAllSnapshot {
        let ledger: LedgerState
        let upgrades: UpgradeState
        let memory: NPCMemoryState
    }

    nonisolated private static func loadAll(
        ledgerURL: URL, upgradeStateURL: URL, memoryURL: URL
    ) async -> LoadAllSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: ledgerURL),
              let ledger = try? decoder.decode(LedgerState.self, from: data)
        else { return nil }

        let upgrades: UpgradeState
        if let uData = try? Data(contentsOf: upgradeStateURL),
           let u = try? decoder.decode(UpgradeState.self, from: uData) {
            upgrades = u
        } else {
            upgrades = .empty
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
