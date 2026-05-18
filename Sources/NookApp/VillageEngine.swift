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
    private var watcher: LedgerWatcher

    init(ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".pixelvillage/ledger.json")) {
        self.ledgerURL = ledgerURL
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.watcher = LedgerWatcher(ledgerURL: ledgerURL)
    }

    func start() {
        watcher.onChange = { [weak self] in
            self?.reload()
        }
        watcher.start()
        reload()
    }

    func stop() {
        watcher.stop()
    }

    func consumePendingBits() {
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
