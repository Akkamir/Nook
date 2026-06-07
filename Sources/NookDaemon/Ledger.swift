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

    func apply(event: TokenEvent, agentName: String?, multiplier: Double = 1.0, to state: inout LedgerState) {
        let bits = event.bits * multiplier
        guard bits > 0 else { return }
        state.pendingBits += bits
        state.totalBits += bits
        state.lastUpdated = Date()

        if let name = agentName {
            var record = state.agents[name] ?? AgentRecord(name: name, totalTokens: 0, bond: 1)
            record.addTokens(event, bits: bits)
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

    func ingestSubject(entry: ParsedEntry, sessionId: String, projectPath: String, agentName: String?, to state: inout LedgerState) {
        // Mirror apply()'s derivation so a session created here keys identically.
        let project = entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? URL(fileURLWithPath: projectPath).lastPathComponent

        // Upsert the session (create if this line precedes any usage-bearing line).
        var session = state.sessions[sessionId] ?? SessionRecord(
            sessionId: sessionId, project: project, projectPath: projectPath,
            agentName: agentName, startedAt: entry.timestamp, lastActivityAt: entry.timestamp,
            inputTokens: 0, outputTokens: 0, totalBits: 0
        )
        session.lastActivityAt = entry.timestamp
        if let agentName { session.agentName = agentName }
        if let branch = entry.gitBranch { session.gitBranch = branch }

        // Task: first real user prompt.
        if session.task == nil, let text = entry.userText {
            let snippet = Self.truncate(text, to: 120)
            session.task = snippet
            emitActivity(&state, agentName: agentName, sessionId: sessionId, kind: "task", payload: snippet)
        }

        // Tool uses: files + commands + counts.
        for tool in entry.toolUses {
            switch tool.name {
            case "Edit", "Write", "MultiEdit":
                session.editCount += 1
                if let path = tool.filePath { newFile(&state, &session, path, agentName, sessionId) }
            case "Read":
                session.readCount += 1
                if let path = tool.filePath { newFile(&state, &session, path, agentName, sessionId) }
            case "Bash":
                session.bashCount += 1
                if let cmd = tool.command {
                    let summary = Self.commandSummary(cmd)
                    if cmd.contains("git commit") {
                        fireOnce(&state, &session, kind: "committing", payload: "git commit", agentName, sessionId)
                    } else if Self.looksLikeTests(cmd) {
                        fireOnce(&state, &session, kind: "testing", payload: summary, agentName, sessionId)
                    }
                }
            default:
                break
            }
        }

        // Deep work threshold.
        if session.editCount >= 10 {
            fireOnce(&state, &session, kind: "deepWork", payload: session.project, agentName, sessionId)
        }

        state.sessions[sessionId] = session
    }

    private func newFile(_ state: inout LedgerState, _ session: inout SessionRecord, _ path: String,
                         _ agentName: String?, _ sessionId: String) {
        guard !session.filesTouched.contains(path) else { return }
        session.filesTouched.append(path)
        if session.filesTouched.count > 20 { session.filesTouched.removeFirst(session.filesTouched.count - 20) }
        emitActivity(&state, agentName: agentName, sessionId: sessionId, kind: "file",
                     payload: URL(fileURLWithPath: path).lastPathComponent)
    }

    private func fireOnce(_ state: inout LedgerState, _ session: inout SessionRecord, kind: String,
                          payload: String?, _ agentName: String?, _ sessionId: String) {
        guard !session.firedKinds.contains(kind) else { return }
        session.firedKinds.append(kind)
        emitActivity(&state, agentName: agentName, sessionId: sessionId, kind: kind, payload: payload)
    }

    private func emitActivity(_ state: inout LedgerState, agentName: String?, sessionId: String,
                              kind: String, payload: String?) {
        state.activitySeq += 1
        state.recentActivity.append(SessionActivityEvent(
            agentName: agentName, sessionId: sessionId, kind: kind, payload: payload, seq: state.activitySeq))
        if state.recentActivity.count > 100 {
            state.recentActivity.removeFirst(state.recentActivity.count - 100)
        }
    }

    static func truncate(_ s: String, to n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n - 1)) + "…"
    }

    static func commandSummary(_ cmd: String) -> String {
        let parts = cmd.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard let first = parts.first.map(String.init) else { return "" }
        if first == "git", parts.count > 1 { return "git \(parts[1])" }
        return first
    }

    static func looksLikeTests(_ cmd: String) -> Bool {
        let c = cmd.lowercased()
        return c.contains("test") || c.contains("pytest")
    }
}

extension Ledger {
    static var production: Ledger {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/ledger.json")
        return Ledger(url: url)
    }
}
