import Foundation
import Observation

@MainActor
@Observable
final class VillageEngine {
    private(set) var totalBits: Double = 0
    private(set) var pendingBits: Double = 0
    private(set) var agents: [String: AgentRecord] = [:]

    private let ledgerURL: URL
    private let decoder: JSONDecoder
    private let watcher: LedgerWatcher
    private var isRunning = false

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
        watcher.onChange = { [weak self] in self?.reload() }
        watcher.start()
        reload()
    }

    func stop() {
        watcher.stop()
        isRunning = false
    }

    func consumePendingBits() {
        // TODO: This only clears the in-memory value; the next reload() will restore it from disk.
        // Track a "consumed offset" or persist the clear to ledger.json if needed.
        pendingBits = 0
    }

    private func reload() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let state = try? decoder.decode(LedgerState.self, from: data)
        else { return }
        totalBits = state.totalBits
        pendingBits = state.pendingBits
        agents = state.agents
    }
}
