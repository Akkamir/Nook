import Foundation
import Observation

@MainActor
@Observable
final class VillageEngine {
    private(set) var totalBits: Double = 0
    private(set) var pendingBits: Double = 0
    private(set) var agents: [String: AgentRecord] = [:]

    private(set) var dayPhase: DayPhase = DayPhase.current()
    private(set) var activeSessions: Set<String> = []
    var newBitEvents: [BitEvent] = []

    private let ledgerURL: URL
    private let decoder: JSONDecoder
    private let watcher: LedgerWatcher
    private var isRunning = false
    private var lastSeenEventSeq: Int = -1
    private var dayNightTimer: DispatchSourceTimer?
    private var sessionTimer: DispatchSourceTimer?
    private let sessionDetector = SessionDetector()
    private let hookServer = ClaudeHookServer()
    private let hookInstaller = ClaudeHookInstaller()

    init(ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".pixelvillage/ledger.json")) {
        self.ledgerURL = ledgerURL
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
        startSessionTimer()
    }

    func stop() {
        watcher.stop()
        dayNightTimer?.cancel()
        dayNightTimer = nil
        sessionTimer?.cancel()
        sessionTimer = nil
        hookServer.stop()
        isRunning = false
    }

    private func startHookServer() {
        hookServer.onEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                let changed = await self.sessionDetector.handleHookEvent(event)
                if changed {
                    self.activeSessions = await self.sessionDetector.detectActive()
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

    private func startSessionTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(120))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.activeSessions = await self.sessionDetector.detectActive()
            }
        }
        timer.resume()
        sessionTimer = timer
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

    private func reload() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let state = try? decoder.decode(LedgerState.self, from: data)
        else { return }
        totalBits = state.totalBits
        pendingBits = state.pendingBits
        agents = state.agents

        let fresh = state.recentEvents.filter { $0.seq > lastSeenEventSeq }
        if !fresh.isEmpty {
            newBitEvents = fresh
            lastSeenEventSeq = fresh.map(\.seq).max() ?? lastSeenEventSeq
        }
    }
}
