import Foundation

final class Ledger {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LedgerState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(LedgerState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: LedgerState) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func apply(event: TokenEvent, agentName: String?, to state: inout LedgerState) {
        let bits = event.bits
        guard bits > 0 else { return }
        state.pendingBits += bits
        state.totalBits += bits
        state.lastUpdated = Date()

        if let name = agentName {
            var record = state.agents[name] ?? AgentRecord(name: name, totalTokens: 0, bond: 1)
            record.addTokens(event)
            state.agents[name] = record
        }

        let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? URL(fileURLWithPath: event.projectPath).lastPathComponent
        if var session = state.sessions[event.sessionId] {
            session.lastActivityAt = event.timestamp
            session.inputTokens += event.inputTokens
            session.outputTokens += event.outputTokens
            session.totalBits += bits
            // Don't clobber a previously resolved agent if this event has none
            // (e.g. .pixelvillage briefly unreadable) — attribution is load-bearing.
            if let agentName { session.agentName = agentName }
            state.sessions[event.sessionId] = session
        } else {
            state.sessions[event.sessionId] = SessionRecord(
                sessionId: event.sessionId,
                project: project,
                projectPath: event.projectPath,
                agentName: agentName,
                startedAt: event.timestamp,
                lastActivityAt: event.timestamp,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                totalBits: bits
            )
        }

        state.eventSeq += 1
        state.recentEvents.append(BitEvent(agentName: agentName, bits: bits, seq: state.eventSeq))
        if state.recentEvents.count > 100 {
            state.recentEvents.removeFirst(state.recentEvents.count - 100)
        }
    }
}

extension Ledger {
    static var production: Ledger {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/ledger.json")
        return Ledger(url: url)
    }
}
